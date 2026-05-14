# SA 语言与编译器 需求文档

## 1. 项目概述

### 1.1 项目代号
**SA** (Symbolic Affine) — 符号化仿射语言。实现与工具链仍保留 `saasm` 作为命令行前缀与文件扩展名（出于与已有讨论/样例的兼容），但语言名称为 **SA**。

### 1.2 定位
这是一门专门为 LLM（大语言模型）生成代码、机器进行形式化验证而设计的**线性所有权汇编语言**。它刻意抛弃所有为碳基生物（人类）设计的语法糖，将"编程语言"降维为一种**带所有权验证的资源调度协议**。

### 1.3 受众契约
- **主要生产者**：LLM（包括小参数模型的级联路由场景）
- **主要消费者**：Referee 验证器 + Zig 降级后端
- **次要受众**：人类工程师只做"一眼扫执行顺序"级别的审查与调试，不承担主要编写任务

### 1.4 不是什么（Non-Goals）
- 不是通用编程语言
- 不追求与现有人类代码生态（libc/std/包管理器）兼容
- 不提供泛型、闭包、Trait、模式匹配、异步关键字、嵌套作用域、面向对象
- 不提供隐式 Drop、隐式类型推导、隐式生命周期推导（NLL）
- 不构建传统 AST，不维护符号作用域表

### 1.5 核心产物（MVP 验收目标）
1. 一份完整可执行的**语言规范白皮书**（< 2000 行，LLM 即读即用）
2. 一个**前端预处理器**（宏展平 Flattener）
3. 一个**Referee 状态机验证器**（O(1) 位掩码扫描）
4. 一个 **SA → LLVM IR + WASM** 发射管线（详见 R14）
5. 基于 Zig 工具链的 **WASM64** 产出管线
6. 一组覆盖所有权边界条件的**测试集**（≥ 99.9% 通过率）

---

## 2. 需求列表

采用 EARS（Easy Approach to Requirements Syntax）格式。

### Requirement 1: 语言符号系统（四大仿射操作符）

**User Story**  
作为 LLM 代码生成端，我需要用极少的符号数量表达所有权的全部状态流转，以最大化 Token 密度、降低上下文占用。

**Acceptance Criteria**
1. WHEN 源码中出现 `=` 前缀 THEN 语言规范 SHALL 定义其为"分配/绑定"操作，目标寄存器进入 `Active` 状态
2. WHEN 源码中出现 `&` 前缀 THEN 语言规范 SHALL 定义其为"借用锁定"操作，原寄存器进入 `Locked` 状态，生成新的借用寄存器进入 `Active(Borrow)` 状态
3. WHEN 源码中出现 `^` 前缀 THEN 语言规范 SHALL 定义其为"消费/Move"操作，原寄存器进入 `Consumed` 终态
4. WHEN 源码中出现 `!` 前缀 THEN 语言规范 SHALL 对借用寄存器解除 `Locked` 锁恢复 `Active`，或对所有权寄存器触发物理内存释放并转为 `Consumed`
5. WHEN 源码中出现成对 `$ ... $` THEN 语言规范 SHALL 将其视为"原生代码逃逸门"，界定符内部原样透传给目标后端（如 Zig），不做任何转义处理
6. WHEN 四大符号同时出现在一行 THEN 规范 SHALL 规定其解析优先级与组合语义，避免歧义

### Requirement 2: 极简线性指令集（ISA）

**User Story**  
作为 Referee 验证器，我需要指令集被压缩到最少的正交原语，使线性扫描能以 O(1) 分支完成状态推进。

**Acceptance Criteria**
1. WHEN 前端输入指令流 THEN 指令集 SHALL 仅包含以下核心指令：
   - `reg = alloc [Size]`（堆内存分配，需配对 `!reg`）
   - `reg = stack_alloc [Size]`（栈帧内存分配，生命周期绑定函数出口，禁止 `^` 移出函数，禁止发射 `!reg`，Referee 在函数出口自动视为已释放）
   - `dst = load src+offset [as T]`（按偏移读取，可选类型标注）
   - `store dst+offset, val [as T]`（按偏移写入）
   - `dst = op a, b`（见下方分组）
   - `jmp L_NAME`（无条件跳转）
   - `br cond -> L_TRUE, L_FALSE`（条件二分跳转）
   - `br_null reg -> L_NULL, L_NOT_NULL`（空指针二分跳转）
   - `call @func(args)`（函数调用）
   - `call_indirect func_ptr(args)`(间接函数指针调用)
   - `return [reg]`（函数返回）
   - `take src+offset`（从内存块中剥离内部指针所有权）
   - `dst = atomic_load src+offset [ordering]`（原子读）
   - `atomic_store dst+offset, val [ordering]`（原子写）
   - `dst, ok = cmpxchg target+offset, expected, new [success_ord] [failure_ord]`（原子 CAS，双返回值：旧值 + 成功位）
   - `dst = atomic_rmw_<OP> target+offset, val [ordering]`（读-改-写原子原语族，`<OP> ∈ {add, sub, and, or, xor, xchg, min, max, umin, umax}`，返回修改前的旧值）
   - `fence [ordering]`（内存栅栏）
2. WHEN 指令行出现 THEN 其 SHALL 严格遵循三地址码格式 `[dst] = [op] [src1] [src2]`（`cmpxchg` 允许二目标格式 `[dst], [ok] = cmpxchg ...`）
3. IF 指令尝试访问未声明的寄存器 THEN Referee SHALL 返回 `Trap: UnknownRegister`
4. WHEN 数值字面量出现 THEN 规范 SHALL 支持以下原生类型集合：
   - 整数：`i8 / i16 / i32 / i64 / u8 / u16 / u32 / u64`
   - 浮点：`f32 / f64`
   - 指针：`ptr`（不透明裸指针，8 字节）
   - 布尔：`i1`（仅用于条件跳转与比较指令返回值）
   - SIMD 向量：`v128`（128 位打包，元素类型由具体 `op` 指令决定，如 `add.f32x4`）
   不支持任何复合类型
5. WHEN `op` 分组需要明确 THEN 规范 SHALL 定义以下指令族：
   - 整数算术：`add / sub / mul / sdiv / udiv / srem / urem / neg`
   - 位运算：`and / or / xor / shl / lshr / ashr / not`
   - 整数比较：`eq / ne / slt / sle / sgt / sge / ult / ule / ugt / uge`
   - 浮点算术：`fadd / fsub / fmul / fdiv / fneg`
   - 浮点比较：`fcmp_eq / fcmp_ne / fcmp_lt / fcmp_le / fcmp_gt / fcmp_ge`
   - 类型转换：`trunc / zext / sext / fptosi / sitofp / uitofp / fptrunc / fpext / bitcast`
   - 指针算术：`ptr_add base, offset_bytes`（产物是裸指针，不参与掩码追踪；但不构成气闸舱违规，详见 R13 `InteriorPtr` 规则）
   - SIMD（最小集）：`add.v128 / sub.v128 / mul.v128 / shuffle.v128 / extract_lane / insert_lane`
6. WHEN `ordering` 出现在原子指令 THEN 其 SHALL 取自 `{relaxed, acquire, release, acq_rel, seq_cst}`（默认 `seq_cst`）
7. WHEN `cmpxchg` 指定 `success_ord` 与 `failure_ord` THEN 其 SHALL 遵循 LLVM 原子约束：`failure_ord` 不得强于 `success_ord`，否则 Flattener 返回 `Trap: InvalidAtomicOrdering`
8. WHEN `stack_alloc` 产物被 `^` Move 或作为 `return` 值返回 THEN Referee SHALL 返回 `Trap: StackEscape`

### Requirement 3: 控制流扁平化（零嵌套）

**User Story**  
作为 LLM 生成端，嵌套大括号极易产生闭合错误；我需要完全扁平的标签跳转控制流以最大化生成稳定性。

**Acceptance Criteria**
1. WHEN 函数定义出现 THEN 语法 SHALL 采用 `@func_name(params) -> ret_type:` 冒号结尾形式，禁止使用花括号 `{}` 包裹函数体
2. WHEN 分支或循环需要表达 THEN 规范 SHALL 强制使用 `L_LABEL:` 标签 + `jmp`/`br` 指令实现
3. IF 源码中出现 `{`, `}`, `if`, `else`, `while`, `for` 关键字 THEN Referee SHALL 在预扫描阶段返回 `Trap: ForbiddenSyntax`
4. WHEN 基本块的最后一条指令不是 `jmp`/`br`/`return` THEN Referee SHALL 返回 `Trap: FallthroughForbidden`
5. WHEN 同名标签出现两次 THEN Referee SHALL 返回 `Trap: DuplicateLabel`

### Requirement 4: 内存所有权状态机（Capability Mask）

**User Story**  
作为 Referee 验证器，我需要一个用位运算就能 O(1) 完成状态比对的掩码模型，而不是基于图论的 NLL 推导。

**Acceptance Criteria**
1. WHEN 任何寄存器产生或被操作 THEN Referee SHALL 在全局注册表中为其维护一个 `u16` Capability Mask（从 v0.1 起扩展自 u8，以容纳 9 位标志）
2. WHEN 状态值被设置 THEN 其 SHALL 严格取自以下标志位集合（可通过按位或组合）：
   - `0x0001` = Active（拥有完整读写与转移权限）
   - `0x0002` = Locked_Read（共享借用锁，可并发读）
   - `0x0004` = Locked_Mut（独占借用锁）
   - `0x0008` = Consumed（终态：已 Move 或已 free）
   - `0x0010` = BorrowView（标记：本寄存器是一个借用视图，`!` 时回溯源寄存器）
   - `0x0020` = FfiBorrow（气闸舱借用：禁止 `^` / `!` 物理释放，仅清跟踪记录）
   - `0x0040` = Untracked（`*` 裸指针产物，Referee 不追踪其生命周期）
   - `0x0080` = Fallible（可失败函数返回值，仅允许被 `?` 操作符作用）
   - `0x0100` = Immutable（`@const` 全局只读数据，禁止 `^` / `!` / 独占借用；仅允许只读 `&` 与 `load`）
   - `0x0200` = InteriorPtr（源寄存器 `&` 借用期间从其内部 `ptr_add` 派生的裸地址；生命周期与源借用同步，解锁源借用时该寄存器自动进入 `Consumed`）
3. WHEN 对处于 `Locked_Mut` 状态的寄存器执行读、写或 `^` Move 操作 THEN Referee SHALL 返回 `Trap: BorrowConflict`
4. WHEN 对处于 `Consumed` 状态的寄存器执行任何操作 THEN Referee SHALL 返回 `Trap: UseAfterMove`
5. WHEN 函数出口存在任何处于 `Active` 或 `Locked_*` 状态的局部寄存器 THEN Referee SHALL 返回 `Trap: MemoryLeak`（不提供隐式 Drop）；`Immutable` 状态的 `@const` 引用与 `stack_alloc` 产物不在此限
6. WHEN 同一内存块被请求第二次可变借用 THEN Referee SHALL 返回 `Trap: DoubleMutableBorrow`
7. WHEN 一个内存块已存在 `Locked_Read` 又被请求 `Locked_Mut` THEN Referee SHALL 返回 `Trap: ReadWriteConflict`
8. WHEN `Immutable` 寄存器被 `^` 或 `!` 或独占借用操作 THEN Referee SHALL 返回 `Trap: ConstMutation`
9. WHEN 普通函数内执行 `ptr_add` 从一个处于 `Locked_Read` 或 `Locked_Mut` 的借用寄存器派生地址 THEN 产物 SHALL 获得 `InteriorPtr` 状态，其源字段记录母借用的寄存器 ID；此寄存器仅允许 `load` / `store`，**禁止 `call` 作为裸指针参数传递给 `@extern`**（防止逃逸）
10. WHEN 源借用寄存器被 `!` 解锁 THEN 所有派生的 `InteriorPtr` 寄存器 SHALL 同步进入 `Consumed`；后续访问必 `UseAfterMove`

### Requirement 5: 函数签名与所有权契约

**User Story**  
作为调用方，我需要在函数签名上直接看出每个参数的所有权走向，不需要阅读函数体推导。

**Acceptance Criteria**
1. WHEN 函数参数声明 THEN 其 SHALL 使用前缀符号明确所有权契约：
   - 无前缀：按值拷贝（仅限原生数值类型：`i8..u64` / `f32` / `f64`）
   - `&`：借用（调用方保持所有权，锁定期间不可被 Move/释放；共享读 vs 独占写由 Referee 的 `Locked_Read` / `Locked_Mut` 位掩码在**调用方上下文**内动态决定，**不在签名层区分**）
   - `^`：Move（调用方失去所有权）
   - `*`：裸指针（仅允许在 `@ffi_wrapper` 或 `@extern` 声明中出现）
2. WHEN 参数 `cap` 为 `&` / `^` THEN 其 `ty` 字段 SHALL **必须等于 `ptr`**；按值传递（无前缀）时 `ty` 可为任意原生数值类型；`*` 参数仅在 `@extern` / `@ffi_wrapper` 中合法，`ty` 必须为 `ptr` 或原生数值。违反时 Flattener 返回 `Trap: InvalidParamType`
3. WHEN 调用点出现 THEN 参数前缀 SHALL 与签名前缀严格一致，否则 Referee 返回 `Trap: CapabilityMismatch`
4. WHEN 函数返回所有权 THEN 签名 SHALL 使用 `-> ^ptr` 标注（返回类型在有 `^` 前缀时恒为 `ptr`），表示被调用方交出所有权给调用方
5. WHEN 函数返回借用 THEN 签名 SHALL 使用 `-> &ptr`；**SA 不做跨函数借用追踪**，调用方需按 R20 合约自行保证调用域内源内存未释放
6. WHEN 函数返回按值结果 THEN 签名 SHALL 使用 `-> T`（`T` 为任意原生数值类型），不加前缀
7. WHEN 函数使用 `$ ... $` 嵌入原生代码 THEN 该块 SHALL 被视为"契约边界"，其内部对寄存器的任何操作都被 Referee 视为对该寄存器的消费（保守策略）
8. WHEN 用户自定义数据结构（如 Rust `struct Vec3`）降级到 SA THEN 其布局 SHALL 通过顶层 `#def Vec3_SIZE = N / #def Vec3_field = +off` 注释性声明表达；函数签名中 **严禁** 出现用户自定义类型名（如 `&Vec3` 必须写作 `&ptr`，注释中说明指向 Vec3 布局）
9. WHEN 调用点需要独占可变访问一个内存块 THEN 其 SHALL 在进入调用前显式以 `=& src` 的形式获取独占借用（Referee 给源寄存器打上 `Locked_Mut` 位），然后以 `&r` 前缀传入；调用返回后显式 `!r` 解锁。语法层**不存在** `&mut` 前缀

### Requirement 6: 数据结构的物理降维

**User Story**  
作为机器语言，我不持有任何高级类型抽象；所有"结构体 / 数组 / 字符串 / 枚举 / Trait" 必须以裸内存块 + 偏移量形式表达。

**Acceptance Criteria**
1. WHEN 需要表达结构体 THEN 其 SHALL 被降维为 `alloc N` 分配的连续字节块 + `+offset` 寻址
2. WHEN 需要表达动态数组或字符串 THEN 其 SHALL 被降维为 24 字节胖指针结构 `[data_ptr(8) | length(8) | capacity(8)]`
3. WHEN 需要表达枚举/Sum Type THEN 其 SHALL 被降维为"4 字节 Tag + 最大 Variant 大小 Payload"的内存块，`match` 语义必须通过 `load tag + br` 展平
4. WHEN 需要表达动态分发 (Trait) THEN 其 SHALL 被降维为 16 字节胖指针 `[data_ptr(8) | vtable_ptr(8)]` + `call_indirect`
5. WHEN 需要表达全局只读常量数据 (VTable / 字符串字面量 / 查找表) THEN 语法 SHALL 支持顶层 `@const NAME = <literal>` 声明（**无类型标注**，字节长度由字面量本身决定），其内存位于 `.rodata` 段，寿命等同于进程生命周期
6. WHEN `@const` 声明被引用 THEN 其 SHALL 被视为具有 `Active + Immutable` 状态的永续寄存器（见 R4 扩展），禁止 `^` Move、`!` 释放、独占借用；仅允许只读 `&` 借用与 `load` 读取
7. WHEN `@const` 内容为 byte 字面量 THEN 语法 SHALL 支持以下书写形式：
   - `hex:\x01\x02...`（每 `\xNN` 表示 1 字节）
   - `utf8:"string"`（UTF-8 编码，**不含结尾 `\0`**；字节长度为字符串 UTF-8 字节数）
   - `repeat:N of BYTE`（N 个同值字节）
   - `struct { field1: N1 = v1, field2: N2 = v2 }`（字段大小显式声明）
   - `vtable { slot1 = @func1, slot2 = @func2 }`（函数指针数组，每槽位 8 字节）
8. WHEN `@const` 用于 VTable THEN 其字段 SHALL 可以引用函数地址；Emitter 产出对应的函数指针数组在 `.rodata`
9. WHEN 需要 Rust `&str` 风格的胖指针字面量 THEN 建议采用 **两步声明**：先 `@const FOO_BYTES = utf8:"..."`，再在运行时构造胖指针（`stack_alloc 16; store +0 &FOO_BYTES; store +8 <len>`）；SA 不提供直接的 Str 字面量糖
10. WHEN 需要表达索引访问 `arr[i]` THEN 其 SHALL 被降维为 `offset = i * element_size; ptr = ptr_add data_ptr, offset; load ptr+0`，并由 LLM/前端自行插入越界检查
11. IF 源码中出现 `a.b.c` 点号属性访问链 THEN Referee SHALL 返回 `Trap: ForbiddenSyntax`，强制使用 `load reg+offset`

### Requirement 7: 伪指令字典（Layout Directive）

**User Story**  
作为 LLM 生成端，心算字节偏移量（+0/+4/+8）容易出错；我需要一种不破坏扁平性的常量替换机制。

**Acceptance Criteria**
1. WHEN 源码顶部出现 `#def NAME = VALUE` 行 THEN 前端预处理器 SHALL 在扫描阶段将其记录为纯文本替换字典
2. WHEN 后续指令引用 `NAME` 符号 THEN 预处理器 SHALL 在 Referee 见到指令前完成字面量展开
3. WHEN 替换发生 THEN 它 SHALL 不建立任何作用域树或符号表，仅执行一维字符串替换
4. IF 同一 `#def` 名被重复定义 THEN 预处理器 SHALL 返回 `Trap: DuplicateDef`
5. WHEN 常量数学表达式出现（如 `+ (%i * 4)`) THEN 预处理器 SHALL 在替换后进行常量折叠，生成纯数字字面量
6. WHEN CLI 提供 `saasm layout` 子命令 THEN 其 SHALL 接受结构体字段描述（名称 + 类型），自动计算对齐与偏移量，输出标准 `#def` 字典文本（见 R7b）

### Requirement 7b: `saasm layout` 布局生成工具（v0.1 辅助工具）

**User Story**  
作为 LLM 或人类开发者，手算复杂结构体的字节偏移量（尤其是混合 `i32` / `f64` 时的对齐填充）极易出错。我需要一个 CLI 工具，输入字段描述，自动输出正确的 `#def` 字典。

**Acceptance Criteria**
1. WHEN 用户执行 `saasm layout --name Entity --fields "id:u32, pos_x:f64, pos_y:f64, hp:i32"` THEN CLI SHALL 输出：
   ```
   #def Entity_SIZE  = 32
   #def Entity_id    = +0
   #def Entity_pos_x = +8
   #def Entity_pos_y = +16
   #def Entity_hp    = +24
   ```
2. WHEN 字段类型为 `i8/u8` THEN 对齐为 1；`i16/u16` 对齐为 2；`i32/u32/f32` 对齐为 4；`i64/u64/f64/ptr` 对齐为 8
3. WHEN 前一个字段结束位置未对齐到下一个字段的对齐要求 THEN 工具 SHALL 自动插入填充字节（padding），并在输出中以注释标注
4. WHEN 结构体总大小未对齐到最大字段对齐 THEN 工具 SHALL 在末尾补齐（尾部 padding），使 `SIZE` 为最大对齐的整数倍
5. WHEN 输出格式被指定为 `--format json` THEN 工具 SHALL 输出 JSON 格式：`{"name":"Entity","size":32,"fields":[{"name":"id","offset":0,"size":4,"ty":"u32"},...]}`
6. WHEN LLM 调用此工具 THEN 其 SHALL 可以直接把输出粘贴到 `.saasm` 文件顶部使用，无需任何修改
7. WHEN 字段类型不在 `{i8,u8,i16,u16,i32,u32,i64,u64,f32,f64,ptr}` 集合内 THEN 工具 SHALL 报错
8. WHEN `--target 32` 被指定 THEN `ptr` 对齐为 4 字节（而非默认的 8 字节），`SIZE` 相应调整

### Requirement 8: 扁平化宏系统（Assembly-Style Macros）

**User Story**  
作为代码生成端，我需要避免重复代码又要保持最终指令流绝对扁平；宏必须是纯文本展开，不生成 AST。

**Acceptance Criteria**
1. WHEN 源码出现 `[MACRO] NAME %p1, %p2 ... [END_MACRO]` THEN 预处理器 SHALL 将其登记为带参文本模板
2. WHEN 源码出现 `EXPAND NAME arg1, arg2` THEN 预处理器 SHALL 用 `arg1`/`arg2` 替换 `%p1`/`%p2` 后整块粘贴到当前位置
3. WHEN 宏体内部出现 `[REP N]...[END_REP]` THEN 预处理器 SHALL 将内部指令复制 N 次，并暴露编译期游标 `%i`（从 0 开始）
4. WHEN 展开后出现寄存器名冲突（同一 Active 名被重复分配）THEN Referee SHALL 返回 `Trap: RegisterRedefinition`（不提供宏卫生机制）
5. WHEN 预处理完成 THEN 最终喂给 Referee 的指令流 SHALL 完全不含 `[MACRO]`、`[REP]`、`EXPAND`、`%i`、`%p*` 等任何宏痕迹
6. IF 宏体内递归调用 EXPAND 自身且无终止条件 THEN 预处理器 SHALL 在展开深度超过阈值（默认 256）时返回 `Trap: MacroRecursionLimit`

### Requirement 9: Referee 验证器（核心裁判）

**User Story**  
作为 LLM 级联路由的裁判层，我需要一个代码行数极少、验证速度达 O(1)-per-line 的状态机引擎。

**Acceptance Criteria**
1. WHEN Referee 接收指令流 THEN 其 SHALL 采用逐行线性扫描，不构建任何树或图结构
2. WHEN 校验单条指令 THEN 其核心操作 SHALL 是一次哈希表查找 + 一次位运算 AND/OR
3. WHEN 校验失败 THEN Referee SHALL 返回结构化 JSON Trap，格式为：
   ```json
   {
     "trap": "<ErrorKind>",
     "line": <number>,
     "register": "<name>",
     "expected_mask": <u8>,
     "actual_mask": <u8>,
     "message": "<short human-readable>"
   }
   ```
4. WHEN 校验通过 THEN Referee SHALL 向下游输出与输入等价的、带状态注解的"已验证指令流"
5. WHEN 全部校验完成 THEN Referee 核心实现 SHALL 限制在 ≤ 2500 行 Zig（MVP 目标；stretch goal ≤ 1500 行，需通过注释抽取重复模式后达成）
6. WHEN 百万行指令流被验证 THEN 其单线程吞吐 SHALL 达到每秒 ≥ 500K 行（MVP 基线；stretch goal ≥ 1M 行）。基准必须在真实代码（含回边、多函数、气闸舱交互）上测量，不得仅以合成直线指令流作为证据

### Requirement 10: 分支汇聚点状态一致性（Phi 检查）

**User Story**  
作为所有权系统，我必须在控制流汇聚的 Label 处保证"同一寄存器在所有入边上的状态一致"，否则产生不可预测行为。

**Acceptance Criteria**
1. WHEN 一个 Label 被多条跳转路径到达 THEN Referee SHALL 求取所有入边上全体寄存器状态的交集
2. IF 同一寄存器在入边 A 上是 `Active`、在入边 B 上是 `Consumed` THEN Referee SHALL 返回 `Trap: PhiStateConflict`
3. WHEN 入边状态一致 THEN Referee SHALL 将该状态作为 Label 起点状态继续扫描
4. WHEN 出现不可达 Label（无入边）THEN Referee SHALL 警告并跳过（非致命）

### Requirement 11: Gas Metering（确定性算力计量）

**User Story**  
作为沙盒托管系统，我需要在执行前就能预估代码的最大算力开销，以便熔断恶意或失控的 LLM 产物。

**Acceptance Criteria**
1. WHEN Referee 扫描完成 THEN 其 SHALL 输出一份 Gas 报告：`{ max_alloc_bytes, max_instruction_steps, call_depth }`
2. WHEN Gas 报告 THEN 其 SHALL 不依赖运行时统计，完全由静态扫描得出
3. WHEN 指令流含无界循环 THEN Referee SHALL 将该循环体的 `max_instruction_steps` 标注为 `unbounded`，由宿主决定是否接受
4. WHEN 宿主传入 Gas 上限 THEN Zig 后端降级时 SHALL 插入计数器，运行期达到上限直接触发 Trap

### Requirement 12: 状态快照与序列化

**User Story**  
作为分离式 Agent 运行时，我需要在任意指令点把执行现场打包成二进制快照，迁移到另一台机器继续运行。

**Acceptance Criteria**
1. WHEN 宿主请求快照 THEN 运行时 SHALL 输出两部分：`CapabilityTable (u8[])` + `MemoryArena (bytes)`
2. WHEN 快照被加载 THEN 另一宿主 SHALL 能在不重初始化的前提下从精确断点恢复执行
3. WHEN 快照产生 THEN 其 SHALL 不依赖 OS 调用栈、不依赖堆上指针绝对地址（使用相对偏移）
4. WHEN 快照体积 THEN 其 SHALL 以字节为单位紧凑编码，不含元数据冗余

### Requirement 13: FFI 边界与气闸舱（Airlock）

**User Story**  
作为内核纯洁的守护者，我需要把"裸指针越狱"物理隔离到专门的 FFI 边界函数中，使核心业务逻辑保持绝对安全；同时通过标准 C-ABI 与任意第三方库（Rust std / UE5 / SQLite / PhysX 等）零成本互操作。

**Acceptance Criteria**
1. WHEN 语法引入第五操作符 `*` THEN 其 SHALL 被定义为"裸指针降级/剥离掩码"，产生的寄存器获得 `Untracked` 掩码，Referee 不追踪其生命周期
2. WHEN 语法引入 `assume_safe reg` THEN 其 SHALL 强制把裸指针升级为具有 `Active` 掩码的受控寄存器（声明沙盒对其生命周期负责）
3. WHEN 语法引入 `assume_borrow reg [, mut]` THEN 其 SHALL 强制把裸指针升级为 `BorrowView + FfiBorrow + Locked_Read` 或 `BorrowView + FfiBorrow + Locked_Mut` 的借用视图；该视图被 `!` 时仅销毁跟踪记录、绝不发射物理 free
4. WHEN 函数带有 `@ffi_wrapper` 前缀 THEN 该函数体内 SHALL 是全工程唯一允许出现 `*` / `assume_safe` / `assume_borrow` 指令的位置
5. IF 普通 `@func` 函数体内出现 `*` / `assume_safe` / `assume_borrow` 指令 THEN Referee SHALL 返回 `Trap: IllegalUnsafeContext`，定位到违规行
6. WHEN 普通 `@func` 函数体内对 `&` 借用寄存器（无论 `Locked_Read` 还是 `Locked_Mut`）使用 `ptr_add` 或从胖指针 `load` 出裸数据指针 THEN 产物 SHALL 自动进入 `InteriorPtr` 状态（见 R4.9），**不触发气闸舱规则**；仅限本函数内 `load` / `store`，禁止作为 `@extern` 参数逃逸
7. IF `InteriorPtr` 寄存器被作为 `@extern` / `@ffi_wrapper` 参数传递 THEN Referee SHALL 返回 `Trap: InteriorPtrEscape`
8. WHEN `@extern` 声明外部函数 THEN 其参数与返回值 SHALL 只允许使用原生数值类型或 `*` 裸指针，不得使用受掩码保护的寄存器
9. WHEN FFI 内存通过 `assume_borrow` 入舱 THEN 沙盒内严禁对其执行 `^` Move 或 `!` 物理销毁；违反时 Referee 返回 `Trap: FfiOwnershipViolation`
10. WHEN 需要让宿主创建并长期托管对象 THEN 契约 SHALL 采用句柄/ID 模式（宿主返回 `i32`/`u64` 句柄而非裸指针），严禁宿主分配内存的所有权流入沙盒
11. WHEN 函数带有 `@export` 前缀 THEN 发射器 SHALL 产出无名称修饰（no name mangling）、符合标准 C-ABI 的可链接符号

### Requirement 14: 双轨发射器（LLVM IR + WASM 二进制直出）

**User Story**  
作为部署端，我需要把已验证的 SA 指令流直接发射为工业级后端格式，不走"生成 Zig 源码→让 Zig 前端再解析一次"这种无谓的往返。

**Acceptance Criteria**
1. WHEN 目标是 Native（`.exe` / `.so` / `.a`）THEN 发射器 SHALL 直接产出 LLVM IR 文本格式（`.ll`），由 `zig cc` / `zig ld` 作为链接器驱动 LLVM 生成原生目标文件并做 O3 优化
2. WHEN 目标是 WASM THEN 发射器 SHALL 在内存中直接拼接 WebAssembly 二进制字节码（`.wasm`），不经过 LLVM
3. WHEN 发射器处理 `= alloc N` THEN 其 SHALL 在 LLVM IR 中生成 `call ptr @malloc(i64 N)`（或可配置的 Arena Allocator 符号），在 WASM 中生成对应的 `call $malloc`
4. WHEN 发射器处理 `!reg`（所有权释放）THEN 其 SHALL 生成 `call void @free(ptr reg)`；对借用释放（`BorrowView` 位标记）SHALL 不发射任何指令
5. WHEN 发射器处理 `load reg+offset as T` THEN 其 SHALL 生成标准 LLVM `getelementptr` + `load` 组合
6. WHEN 发射器处理 `store reg+offset, val as T` THEN 其 SHALL 生成对应 `getelementptr` + `store`
7. WHEN 发射器处理 `$...$` 原生逃逸块 THEN 其 SHALL 原样把界定符内的字节作为独立的 LLVM IR 片段或内联汇编块插入
8. WHEN 发射器处理 `jmp`/`br`/`br_null` THEN 其 SHALL 生成 LLVM IR 的 `br label %L_X` / `br i1 %c, label %L_T, label %L_F`（原生扁平控制流，无需 labeled switch）
9. WHEN 发射器处理 `@export` 函数 THEN 其 SHALL 生成无名称修饰（no name mangling）的 `extern "C"` 兼容符号，可被任意 C/C++/Rust 静态库链接
10. WHEN 发射器处理 `@extern` 声明 THEN 其 SHALL 在 LLVM IR 顶部生成 `declare` 语句，在 WASM 中生成 `import` 段
11. WHEN Native 链接完成 THEN 输出 SHALL 不再依赖任何 Zig 运行时（Zig 仅作 LLVM 驱动器与跨平台链接器使用）

### Requirement 15: WASM64 产出管线

**User Story**  
作为前端/边缘部署方，我需要最终产物是体积袖珍、可突破 4GB 内存限制的 .wasm 模块。

**Acceptance Criteria**
1. WHEN 完整工具链被调用 THEN `.saasm → .wasm` 端到端流程 SHALL 输出单一 `.wasm` 文件，不经过任何 Zig 源码往返
2. WHEN `.wasm` 被加载 THEN 其导出符号 SHALL 完全兼容 WASI / 标准 C-ABI
3. WHEN 简单 Hello-Compute 样例编译完成 THEN 其 `.wasm` 体积 SHALL ≤ 32 KB
4. WHEN 运行在支持 memory64 的 runtime（如 Wasmtime/Wasmer 最新版）THEN 其 SHALL 能寻址 > 4 GB 堆内存
5. WHEN `@sys_*` 内建原语在 WASM 目标下编译 THEN 其 SHALL 被映射为 WASI 导入（`fd_read` / `fd_write` 等）；若目标环境不支持 WASI THEN 编译器 SHALL 在发射前拒绝并报错

### Requirement 16: CLI 三模驱动（run / build-exe / build-wasm）

**User Story**  
作为开发者或 LLM，我需要像 `bun` / `deno` 那样一行命令就能跑通 SA 源码，或者打包成跨平台独立可执行文件，或者降级为沙盒 WASM，而不需要配置任何外部工具链。

**Acceptance Criteria**
1. WHEN 用户执行 `saasm run <file.saasm> [args...]` THEN CLI SHALL 走完 Flattener + Referee + 内存解释器/JIT，直接在本进程内执行 SA 代码，拥有宿主操作系统权限（文件读写、终端打印、进程退出码）
2. WHEN 用户执行 `saasm build-exe <file.saasm> [-o out]` THEN CLI SHALL 依次运行 Flattener + Referee + LLVM IR 发射器 + `zig cc` 链接器，产出当前平台的独立原生可执行文件
3. WHEN 用户执行 `saasm build-wasm <file.saasm> [-o out.wasm]` THEN CLI SHALL 依次运行 Flattener + Referee + WASM 二进制发射器，产出 `.wasm` 文件（wasm32 或 wasm64 由 `--target` 参数控制）
4. WHEN 用户执行 `saasm build-obj <file.saasm> -o out.o` THEN CLI SHALL 产出可被任意 C/C++/Rust 工程链接的标准目标文件
5. WHEN 任一子命令遇到 Referee Trap THEN CLI SHALL 以非零退出码终止，并把结构化 JSON Trap 打印到 stderr
6. WHEN CLI 自身被分发 THEN 其 SHALL 是单一静态可执行文件，不依赖 libc 外的任何运行时库

### Requirement 17: 内建系统原语 `@sys_*`

**User Story**  
作为完全独立可运行的语言，我需要内建最小必要的系统调用原语（打印、文件读写、进程控制），无需用户配置任何外部 std 桥接；这些原语在不同目标下自动降级到对应的平台 ABI。

**Acceptance Criteria**
1. WHEN 源码调用 `@sys_print(*msg_ptr, len)` THEN 发射器 SHALL 在 Native 目标下映射到 `write(1, ...)`，在 WASM 目标下映射到 `fd_write`
2. WHEN 源码调用 `@sys_read_file(*path_ptr, path_len, *out_len_ptr) -> *buffer` THEN 发射器 SHALL 在 Native 下映射到 libc `open+read+close` 组合并由运行时分配缓冲区，在 WASM 下映射到 WASI `path_open+fd_read`
3. WHEN 源码调用 `@sys_write_file(*path_ptr, path_len, *data_ptr, data_len) -> i32` THEN 发射器 SHALL 对应映射到 Native `open+write+close` 或 WASI 等价调用
4. WHEN 源码调用 `@sys_exit(code)` THEN 发射器 SHALL 映射到平台退出原语
5. WHEN 源码调用 `@sys_argv(index) -> *str_ptr` / `@sys_argc() -> i32` THEN 发射器 SHALL 暴露进程参数接口
6. WHEN `@sys_*` 原语被调用 THEN Referee SHALL 视其为普通函数调用参与所有权检查；若传入 `*` 裸指针 THEN 调用点必须处于 `@ffi_wrapper` 内
7. WHEN 沙盒模式下某个 `@sys_*` 原语在目标运行时（如纯引擎内嵌 WASM）不可用 THEN 编译器 SHALL 在发射前报错，不得生成静默失败的空壳代码

### Requirement 18: 错误传播与 Panic 模型

**User Story**  
作为系统语言，我需要一套统一的错误传播原语，使上层工具（smrustc / 业务逻辑）能把 `Result<T,E>` / `Option<T>` / panic 等高级概念一致地降级为 SA 指令，而不是让每个前端各自重新发明错误返回协议。

**Acceptance Criteria**
1. WHEN 函数返回类型带后缀 `!` THEN 该函数 SHALL 被视为"可失败函数"（fallible），其返回值在 ABI 层用一个 `{u32 status, T value}` 的 2 字段结构体表达（类似 Rust 的 `Result<T,u32>` 但锁定为 C-ABI）
2. WHEN 源码中出现 `? reg` 操作符 THEN 其 SHALL 被视为"错误传播"：若 `reg.status != 0` 则立即 `return reg`，否则取出 `reg.value` 继续使用
3. WHEN 发射器处理 `? reg` THEN 其 SHALL 生成两条等价的 SA 指令序列（`br_ok reg -> L_CONT, L_EARLY_RETURN` + `L_EARLY_RETURN: return reg`）而不是引入新指令类型
4. WHEN 源码调用 `panic(code)` 原语 THEN 其 SHALL 在 Native 目标下映射到 `__sa_panic(code, 0, 0)` 运行时函数（写 `PANIC: code=<N>` 到 stderr 并 `_exit(128 + (code & 0x7F))`），在 WASM 目标下映射到 `unreachable` opcode
5. WHEN 源码调用 `panic_msg(code, *str_ptr, str_len)` 原语 THEN 其 SHALL 在 Native 目标下映射到 `__sa_panic(code, str_ptr, str_len)`（stderr 写 `PANIC[code]: <msg>`），在 WASM 目标下先 `fd_write(2, msg)` 再 `unreachable`；`str_ptr` 可来自 `@const` 或 `@ffi_wrapper` 传入，Referee 视为只读借用
6. WHEN 源码使用标准 panic code 字典 THEN 其 SHALL 采用以下约定（可被覆盖 `#def`）：
   - `100` = DivByZero
   - `101` = OutOfBounds
   - `102` = Unreachable
   - `103` = AssertionFailed
   - `104` = IntegerOverflow
   - `105` = NullDeref
   - `106` = MissingVariant（match 穷尽兜底）
   - `107` = AllocFailed
   - `108`–`127` = 保留
   - `128`–`255` = 用户自定义
7. WHEN Referee 扫描函数体 THEN 若某路径在 `?` 早返回分支上存在未释放的 `Active` 寄存器 THEN 其 SHALL 返回 `Trap: EarlyReturnLeak`，强制前端在早返回前显式 `!reg`
8. WHEN Referee 扫描到 `panic` / `panic_msg` 指令 THEN 其 SHALL 视其为函数终止点（类似 `return`），但**不要求**当前作用域的所有权寄存器已释放（panic 代表不可恢复崩溃，宿主进程即将终止，内存泄漏无意义）
9. WHEN 源码不使用错误传播 THEN 规范 SHALL 兼容纯整数返回码约定（`-> i32` 返回，`0` 表示成功），错误传播仅在显式标注 `!` 后缀时启用

### Requirement 19: 调试信息与上游 Source Map

**User Story**  
作为开发者，当 SA 编译出的 `.exe` 崩溃或需要单步调试时，我需要看到**上游业务语义**（例如 smrustc 编译的 Rust 源码行号、或 LLM 生成 SA 时的高层意图注释），而不是只看到 SA 行号。

**Acceptance Criteria**
1. WHEN 源码中出现 `#loc "file.rs":line:col` 伪指令 THEN Flattener SHALL 将其记录为下一条真实指令的"上游位置注解"，不参与指令流
2. WHEN Referee 产出 `Trap` THEN Trap 报告 SHALL 包含 `upstream_loc: { file, line, col } | null` 字段
3. WHEN LLVM IR Emitter 发射指令 THEN 其 SHALL 为每条指令生成对应的 DWARF `!DILocation` 元数据（指向 `upstream_loc`，缺失时 fallback 到 SA 行号）
4. WHEN WASM Emitter 发射指令 THEN 其 SHALL 生成标准 `name` 自定义段与 DWARF-in-WASM 调试段（可通过 `--no-debug` 关闭以缩减体积）
5. WHEN 用户调用 `saasm build-exe -g` THEN 产物 SHALL 在 GDB / LLDB 中能以上游文件名 + 行号做断点与单步
6. WHEN Runtime Panic 发生 THEN 栈回溯 SHALL 优先显示上游文件行号，SA 行号作为括号备注

### Requirement 20: 前端降级合约（Frontend Lowering Contract）

**User Story**  
作为 smrustc（或任意写 SA 代码的前端）的实现者，我需要一份明确的合约说明：哪些高级语义**必须**由前端展平后再交给 SA，哪些由 SA 兜底。否则前端"机械映射"的边界不清楚，上游工具会变成另一种 NLL 推导器。

**Acceptance Criteria**
1. WHEN 前端遇到词法作用域结束 `}` THEN 其 SHALL 对该作用域内所有未被 `^`/`!` 处理的 `Active` / `Locked_*` 寄存器显式发射 `!reg`；SA 不提供隐式 Drop
2. WHEN 前端遇到 `return` THEN 其 SHALL 先发射所有作用域的显式释放指令，再发射 `return`；在多个 `return` 路径上 SHALL 保证 Phi 汇聚点的释放状态一致
3. WHEN 前端遇到分支合流（Phi） THEN 其 SHALL 为每个在一路分支中被 `^`/`!` 处理、在另一路分支中未处理的寄存器补齐释放指令，使两路到达同一 Label 时 `CapabilityMask` 按位交集合法
4. WHEN 前端实现单态化（如 smrustc 处理泛型）THEN 其 SHALL 在生成 SA 指令前完成所有 `T` 的具体化，SA 不接收任何未实例化的类型变量
5. WHEN 前端实现模式匹配（如 Rust `match`） THEN 其 SHALL 展平为 `load tag + br` 序列；SA 不提供 match 原语
6. WHEN 前端实现闭包（Lambda Lifting） THEN 其 SHALL 生成匿名环境结构体 + 普通函数；SA 不识别闭包概念
7. WHEN 前端实现 `async` THEN 其 SHALL 做 CPS 转换或生成状态机结构体；SA 不识别 async/await
8. WHEN 前端希望复用 Phi 一致性分析 THEN SA 工具链 SHALL 提供一个 helper 库 `libsa_scope.{a,zig}`（非必需依赖），可被前端调用完成作用域跟踪与自动释放插入
9. WHEN 前端违反本合约 THEN 其产出的 SA 代码 SHALL 在 Referee 上必然失败（这是设计意图，不是缺陷）；前端开发者 SHALL 在测试期通过 Referee 反馈调试自己的降级逻辑

### Requirement 21: AutoBevy ECS — 最低优先级 Stretch Demo（非 MVP 验收必选项）

**User Story**  
作为语言架构的可行性展示，我希望用 SA 重构一个极简 ECS 运行时，但这**不是 MVP 验收的硬指标**，而是全项目**最低优先级**的 post-MVP stretch goal；MVP 只要求 1K 实体冒烟通过，1M 实体 + Bevy 性能对标留到 post-MVP。

**Acceptance Criteria**
1. WHEN AutoBevy 最低优先级 Demo 被实现 THEN 其 SHALL 至少包含：Component 注册、Entity 生成、System 注册、并行调度器（复用 Referee CapabilityMask）
2. WHEN 多个 System 被注册 THEN SA 静态并行分析器 SHALL 在运行前扫描其对 Component Buffer 的独占/共享借用请求（`Locked_Mut` vs `Locked_Read`），输出互斥正确的可并行组
3. WHEN 最低优先级 Demo 运行 1K 实体 1 帧 THEN 其 SHALL 在 Wasmtime 中跑通并输出预期结果
4. WHEN 最低优先级 Demo 编译到 WASM64 THEN 其产物 SHALL 可在 Wasmtime 中执行
5. _[最低优先级, post-MVP stretch]_: 1M 实体 1 帧 的耗时对标 Bevy ±30% 窗口。此指标依赖 SIMD ISA（R2.5）、并行线程池、细粒度缓存布局优化，在 MVP 阶段不强制达成

### Requirement 22: 测试集（Referee 行为基线）

**User Story**  
作为实现方，我需要一套覆盖所有边界条件的测试用例，确保任何 Referee 重写都保持语义一致。

**Acceptance Criteria**
1. WHEN 测试集被提交 THEN 其 SHALL 至少包含以下类别，每类 ≥ 10 个用例：
   - 正常所有权流转（alloc/borrow/release/move/free）
   - 双重可变借用冲突
   - Use-After-Move
   - 借用期间 Move
   - 内存泄漏（未释放即出口）
   - Phi 汇聚点状态冲突
   - 宏展开后状态合法/非法
   - 宏递归深度超限
   - 禁用语法（`{}`/`.`/`if`）触发
   - FFI 气闸舱违规（普通函数内出现 `*` / `assume_*`）
   - FFI 内存越界销毁（`^` 或 `!` 作用于 `assume_borrow` 结果）
   - 错误传播早返回 `?` 在未释放寄存器时触发 `EarlyReturnLeak`
   - 原子操作与内存栅栏的 ordering 语义
   - **`InteriorPtr` 生命周期**：派生于 `&` 的内部指针在母借用释放后访问必 `UseAfterMove`
   - **`InteriorPtrEscape`**：试图把 `InteriorPtr` 作为 `@extern` 参数传出必 Trap
   - **`StackEscape`**：`stack_alloc` 产物被 `^` 或 `return` 必 Trap
   - **`ConstMutation`**：对 `@const` 寄存器 `^` / `!` / 独占借用必 Trap
   - **`atomic_rmw` 族语义**：`add` / `sub` / `xchg` / `cmpxchg` 的双返回值正确性
   - **`panic` 与 `panic_msg`**：两种调用均为函数终止点，不要求所有权清理
2. WHEN 测试集被执行 THEN 综合通过率 SHALL ≥ 99.9%
3. WHEN 新版本 Referee 发布 THEN 其 SHALL 100% 通过基线测试集方可合入主线

### Requirement 23: 语法白皮书（LLM 即读即用）

**User Story**  
作为被级联调用的任意 LLM，我必须在不经过微调的前提下，仅凭 System Prompt 阅读白皮书就能生成合法的 SA 代码。

**Acceptance Criteria**
1. WHEN 白皮书产出 THEN 其总行数 SHALL ≤ 2000 行
2. WHEN 白皮书包含章节 THEN 其 SHALL 至少覆盖：
   - 五符号契约（`=` / `&` / `^` / `!` / `*`）与 `$...$` 逃逸门
   - 指令集 ISA 表（含整数/位运算/浮点比较全谱 `fcmp_{eq,ne,lt,le,gt,ge}`/类型转换/SIMD/原子 load/store/cmpxchg/rmw 族/fence/`stack_alloc`/`ptr_add`）
   - 控制流扁平化规则与 CFG 汇聚点 Phi 要求
   - Capability Mask 9 位真值表（含 `FfiBorrow` / `Untracked` / `Fallible` / `Immutable` / `InteriorPtr`）
   - 宏 / REP / EXPAND 用法
   - FFI 气闸舱（`@ffi_wrapper` / `assume_safe` / `assume_borrow` / 句柄模式）+ `InteriorPtr` 内部指针规则
   - `@const` 全局只读数据与 VTable 构造
   - `@sys_*` 内建原语表与 Native / WASI 双轨映射
   - 错误传播 `!` 后缀 / `?` 操作符 / `panic(code)` / `panic_msg(code, *s, len)` 原语
   - **标准 Panic Code 字典**（见 R18.6，复制粘贴到白皮书附录）
   - `#loc` 源码映射伪指令
   - 前端降级合约摘要（R20）
   - Rust → SA → LLVM IR 对比样例（≥ 5 组，必须覆盖：结构体字段访问 / Option+`?` / dyn Trait+VTable / async 单步骤 poll / Rc clone+drop）
   - Referee Trap 代码表（含 `InteriorPtrEscape` / `StackEscape` / `ConstMutation` / `InvalidAtomicOrdering`）
3. WHEN 发布前 LLM Pilot 实验被执行 THEN 规范 SHALL 包含以下验证协议：
   - 从 10 种基础用例（alloc/borrow/loop/branch/FFI/错误传播/结构体字段偏移/数组索引/递归/双缓冲）各抽 3 个变种共 30 题
   - 以 GPT-4o / Claude Opus / DeepSeek-Coder 三个主流 LLM 分别执行零训练生成
   - 记录首次通过 Referee 的比例作为**实测 baseline**，不预设 KPI 数字
4. WHEN Pilot baseline < 50% THEN 项目组 SHALL 在 MVP 冻结前讨论是否增加一层"LLM-friendly 伪嵌套前端"（将 `{}` + `if/else` 在文本层展平为 SA）；此讨论的结论纳入 post-MVP 路线图
5. WHEN 白皮书输出 THEN 其格式 SHALL 同时提供 Markdown 与纯文本（.txt）两种版本

### Requirement 24: `#mode compact` 中缀糖（v0.2 可选前处理器）

**User Story**  
作为偶尔需要手写 SA 原型或 demo 的工程师/LLM，在所有权符号之外，我希望用日常算术/位运算中缀写法降低心智负担；但这种糖只能以**可选、严格受控**的方式引入，不得动摇 Referee 的 O(1) 线性扫描与零 AST 红线。

**Acceptance Criteria**
1. WHEN 源码顶部（首个 `@func` / `@const` / `@extern` / `@export` 之前）出现 `#mode compact` 伪指令 THEN Flattener SHALL 启用"紧凑糖"展开阶段；否则走默认严格模式，源码中出现任何中缀算术都视为语法错误
2. WHEN 紧凑糖被启用 THEN 以下 **8 条且仅 8 条** 中缀形态 SHALL 被 Flattener 在预处理期做纯文本替换：
   - `dst = a + b` → `dst = add a, b`
   - `dst = a - b` → `dst = sub a, b`（二元）
   - `dst = -a`    → `dst = neg a`（一元，`-` 仅在操作数前且无左操作数时触发）
   - `dst = a * b` → `dst = mul a, b`
   - `dst = a / b` → `dst = udiv a, b`（默认无符号；有符号除必须写 `sdiv`）
   - `dst = a % b` → `dst = urem a, b`（默认无符号；有符号余必须写 `srem`）
   - `dst = a & b` → `dst = and a, b`
   - `dst = a | b` → `dst = or a, b`
   - `dst = a ^ b` → `dst = xor a, b`（中缀 `^` 仅在双目位置触发，不与所有权前缀 `^` 冲突）
3. WHEN 紧凑糖展开 THEN 其 SHALL 仅做**单次一行内**的文本替换，不支持优先级组合（如 `dst = a + b * c` 必 Trap `CompactMultipleInfix`）；复合表达式强制拆成多行
4. WHEN 源码混用紧凑中缀与其它关键字形态 THEN Flattener SHALL 全部接受；替换后产出的指令数组 **严格等于** 直接用关键字形态手写时的产出（即：糖只存在于源码文本层，指令层 Referee 永远看不到 `+` `-` `*` `/` `%` `&` `|` `^` 作为中缀）
5. WHEN `#mode compact` 未启用 THEN 源码中出现 `+` `-` `*` `/` `%` 作为中缀 SHALL 触发 `Trap: InfixSugarDisabled`
6. WHEN `#mode compact` 出现第二次 / 出现在首个顶层声明之后 THEN Flattener SHALL 返回 `Trap: InvalidModeDirective`
7. WHEN 紧凑糖产生的替换行与手写关键字行共存 THEN Referee 的 JSON Trap 报告 SHALL 在 `source_line` 字段指向原始行号，并在可选的 `original_text` 字段保留糖形式文本以便 LLM 反向修复
8. WHEN 未来语言升级引入更多中缀形态（如 `<` `>` `==`） THEN 扩展 SHALL 通过新增 `#mode compact-v2` 以版本化方式引入，禁止扩充 v1 的 8 条形态清单
9. **Non-Goals（刻意禁止）**：
   - 不支持操作符优先级（`a * b + c` 无法一行表达，必须拆成 `tmp = a * b; d = tmp + c`）
   - 不支持中缀比较（`<` `>` `==` `!=` `<=` `>=`），必须用 `slt`/`sgt`/`eq` 等关键字
   - 不支持短路 `&&` / `||`（SA 无短路语义）
   - 不支持链式调用 `a.b.c`（已在 R3.3 被禁）
   - 不支持自动类型推导；类型标注 `as T` 不受糖影响

**Rationale**：
- 收益：Rust/C 风格算术在源码文本层节约约 3–5% token，降低手写心智负担
- 代价：Flattener 增加约 80–120 行正则/状态机，新增 3 个 Trap 类型
- 风险控制：8 条白名单 + 严格单目/双目判别 + 禁优先级 + 版本化扩展，避免"一步滑向重建 C"

---

### Requirement 25: VTable 签名静态校验（v0.3）

**User Story**  
作为 Referee 验证器，当 `call_indirect` 通过 VTable 间接调用函数时，我需要在编译期校验调用点的参数 tuple 与 VTable 槽位声明的函数签名是否一致，避免 ABI 不匹配导致的运行时段错误。

**Acceptance Criteria**
1. WHEN `@const NAME = vtable { slot = @func }` 声明时 THEN Referee SHALL 记录每个槽位对应函数的完整签名 tuple `[(cap_prefix, ty)]`
2. WHEN `call_indirect` 指令引用某 VTable 槽位 THEN Referee SHALL 在编译期比对调用点参数 tuple 与槽位声明的 tuple
3. IF 参数数量、cap_prefix 或 ty 任一不匹配 THEN Referee SHALL 返回 `Trap: VTableSignatureMismatch`
4. WHEN VTable 来自 FFI（外部传入的裸指针）THEN 此校验 SHALL 不适用（因为 Referee 无法获知外部 VTable 的签名），由气闸舱 `assume_borrow` 的保守策略兜底
5. WHEN 校验通过 THEN 其 SHALL 为零运行时开销（纯编译期静态分析，不注入任何 runtime 代码）

### Requirement 26: `libsa_async` 异步状态机宏模板（v0.3）

**User Story**  
作为前端（smrustc / LLM），async/await 的 CPS 展平产生 40x 代码膨胀（案例 23），我需要一套标准化的宏模板来自动生成状态机骨架，而不是每次手写 120 行 SA。

**Acceptance Criteria**
1. WHEN `libsa_async` 被引入 THEN 其 SHALL 以 SA 的 `[MACRO]` 系统（R8）为基础，提供以下标准宏模板：
   - `[MACRO] ASYNC_CTX_DEF %name, %fields...`：生成状态机上下文结构体的 `#def` 布局
   - `[MACRO] ASYNC_POLL_PROLOGUE %ctx, %state_field`：生成 state 分发跳转表骨架
   - `[MACRO] ASYNC_AWAIT_POINT %ctx, %state_field, %state_id, %poll_fn, %take_fn, %result_field`：生成单个 await 点的 poll/error/done 三路分支
   - `[MACRO] ASYNC_RETURN_PENDING`：生成公共 Pending 返回块
2. WHEN 前端使用这些宏 THEN 其 SHALL 通过 `EXPAND` 调用，展开后的指令流与手写等价（P30 精神的延伸）
3. WHEN 展开后的代码被 Referee 扫描 THEN 其 SHALL 与手写 SA 完全等价——宏不引入任何新语义，仅是文本模板
4. WHEN `libsa_async` 被分发 THEN 其 SHALL 以 `.saasm` 文本文件形式提供（可被 `@import` 或 Flattener 的文件拼接机制引入），不依赖任何 C-ABI 库
5. WHEN 前端不使用 `libsa_async` THEN 其 SHALL 仍可手写等价的 SA 代码（宏是便利，不是强制）
6. **Non-Goal**：SA 语法层不引入 `@async` / `await_state` 等新关键字；不引入隐式展开；不引入跨 await 变量的自动存取推导

### Requirement 27: 发射产物诊断级别（v0.3）

**User Story**  
作为部署方，我需要明确 SA 编译产物在不同构建模式下的安全保障级别，以便在性能与安全之间做出知情选择。

**Acceptance Criteria**
1. WHEN 用户执行 `saasm build-exe` 或 `saasm build-wasm`（默认 `--release`）THEN 产物 SHALL 不包含任何 Referee 运行时代码；所有所有权校验已在编译期完成，Release 产物零运行时开销
2. WHEN 用户指定 `--debug-gas` THEN 产物 SHALL 在每个函数入口/基本块头部插入 gas 计数器自增指令；超过 `gas_set_limit` 阈值时触发 `Trap: GasExceeded`（R11.4 的运行时实现）
3. WHEN 用户指定 `--debug-san` THEN 产物 SHALL 在 `alloc` / `!free` 点插入红黑树/哈希表簿记，用于运行期侦测 Use-After-Free 和 Double-Free（类似 ASAN 的轻量版）；此模式下性能损耗预期 2-5x
4. WHEN `--debug-san` 检测到 UAF/Double-Free THEN 其 SHALL 输出结构化 JSON 报告（含 `upstream_loc`），格式与 Referee 的 Trap 报告一致
5. WHEN `--release` 模式下发生段错误 THEN 其 SHALL 不是 SA 的责任——这意味着前端降级合约（R20）被违反，或 FFI 气闸舱外的宿主代码有 bug
6. WHEN 三种模式被文档化 THEN 白皮书 SHALL 在"构建模式"章节明确说明各模式的安全保障边界与性能代价

---

### Requirement 28: 接口契约文件 `.saasm-iface`（v0.4 — 并行开发基建）

**User Story**  
作为多人/多 LLM 并行开发同一 APP 的协作者，我需要一种轻量级的接口契约文件，使得 A 和 B 可以同时开发不同模块，互不阻塞，只要接口文件先冻结即可。

**Acceptance Criteria**
1. WHEN 开发者创建 `module.saasm-iface` 文件 THEN 其 SHALL 仅包含 `@extern` 函数签名声明（含 `cap_prefix` + `ty` + 返回类型 + `!` 后缀），不包含函数体
2. WHEN 另一个 `.saasm` 文件通过 `@import "module.saasm-iface"` 引入接口 THEN Flattener SHALL 将其中的 `@extern` 声明注入当前编译单元
3. WHEN Referee 校验调用点 THEN 其 SHALL 使用 `.saasm-iface` 中声明的签名 tuple 做 `CapabilityMismatch` 校验，**无需**实际函数体存在
4. WHEN 接口文件与实现文件的签名不一致 THEN 链接期（`zig cc`）SHALL 报 symbol type mismatch 错误；Referee 层面在各自编译单元内独立通过
5. WHEN 多个 `.saasm` 文件引用同一 `.saasm-iface` THEN 它们 SHALL 可以被**完全并行**编译（各自独立跑 Flattener + Referee + Emitter），最后一步链接合并
6. WHEN `.saasm-iface` 文件被修改 THEN CI SHALL 自动检测哪些依赖方需要重新验证（通过文件哈希比对）
7. WHEN 接口文件包含所有权语义注释 THEN 其 SHALL 支持可选的 `// @contract: consumes data` 风格注释（纯文档性质，Referee 不解析，但 `libsa_scope` helper 可读取）

### Requirement 29: 版本化布局文件 `.saasm-layout`（v0.4 — 并行开发基建）

**User Story**  
作为多人协作团队，共享数据结构的内存布局（如 Entity / Component / Message）是最常见的冲突源。我需要一种版本化的布局声明文件，使布局变更可追踪、可检测。

**Acceptance Criteria**
1. WHEN 团队创建 `entity.saasm-layout` 文件 THEN 其 SHALL 仅包含 `#def` 常量声明 + 一个 `#version N` 元数据行
2. WHEN `.saasm` 文件通过 `@import "entity.saasm-layout"` 引入布局 THEN Flattener SHALL 记录该文件引用的 `#version` 值
3. WHEN 布局文件的 `#version` 递增 THEN CI SHALL 自动扫描所有引用方，标记为"需要重新验证"
4. WHEN 两个 `.saasm` 文件引用了同一布局文件的**不同版本** THEN 链接期 SHALL 报 `Trap: LayoutVersionConflict`（通过在 `.o` 文件中嵌入版本元数据实现）
5. WHEN 布局文件被修改但 `#version` 未递增 THEN CI SHALL 发出警告（非致命，但阻断 merge）
6. WHEN 布局文件格式 THEN 其 SHALL 为：
   ```
   #version 3
   #def Entity_SIZE = 32
   #def Entity_id   = +0
   #def Entity_pos  = +8
   #def Entity_vel  = +16
   #def Entity_hp   = +24
   ```

### Requirement 30: 函数粒度增量编译（v0.4 — 并行开发基建）

**User Story**  
作为大型项目的开发者，当我只修改了一个函数时，不应该重新编译整个文件的所有函数。SA 的 Referee 已经是逐函数验证的，发射器也应该支持逐函数产出。

**Acceptance Criteria**
1. WHEN `saasm build-obj` 被调用 THEN 其 SHALL 支持 `--incremental` 模式：按函数粒度产出独立的 `.o` 文件（每个函数一个 `.o`）
2. WHEN 源文件中某个函数未修改（通过函数体哈希比对）THEN 增量模式 SHALL 跳过该函数的 Emitter + zig cc 阶段，直接复用上次的 `.o`
3. WHEN 增量模式被启用 THEN 最终链接 SHALL 把所有函数的 `.o` 合并为单一产物
4. WHEN 函数之间无跨函数分析依赖（SA 的设计保证）THEN 增量编译的正确性 SHALL 不依赖编译顺序
5. WHEN 增量缓存目录 THEN 其 SHALL 位于 `.sa-cache/` 下，按函数名哈希组织
6. WHEN `--incremental` 与 `--debug-san` 同时启用 THEN 每个函数的 `.o` SHALL 独立包含 sanitizer 簿记入口（不依赖全局状态）

---

### Requirement 31: 包管理与依赖解析 `sa.pkg`（v0.5 — 生态基建）

**User Story**  
作为 LLM 或人类开发者，当项目规模增长到多文件/多模块时，我需要一种声明式的依赖管理机制，使得"引入别人写的 SA 库"像 `cargo add` / `go get` 一样简单，而不是手动拷贝 `.saasm` 文件。

**Acceptance Criteria**
1. WHEN 项目根目录存在 `sa.pkg` 文件 THEN CLI SHALL 识别其为包描述文件，格式为：
   ```
   #pkg name = "my_app"
   #pkg version = "0.1.0"
   #pkg deps = [
       { name = "sa_std", version = "0.5.0", source = "https://registry.sa-lang.org/sa_std" },
       { name = "sa_http", version = "0.1.0", source = "./local_libs/sa_http" }
   ]
   ```
2. WHEN `saasm build-exe` / `build-wasm` / `build-obj` 被调用 THEN CLI SHALL 自动解析 `sa.pkg` 中的依赖，按拓扑序编译所有依赖包
3. WHEN 依赖包被引入 THEN 其 `.saasm-iface` 接口文件 SHALL 被自动注入当前编译单元（等价于 `@import`）
4. WHEN 依赖包的 `.saasm-layout` 布局文件存在 THEN 其 `#def` 常量 SHALL 被自动注入（带命名空间前缀避免冲突：`pkg_name.FIELD_NAME`）
5. WHEN 两个依赖包声明了同名 `@export` 函数 THEN 链接期 SHALL 报 `Trap: DuplicateExportSymbol`
6. WHEN 依赖源为远程 URL THEN CLI SHALL 支持 `saasm pkg fetch` 命令下载到本地 `.sa-cache/deps/` 目录
7. WHEN 依赖源为本地路径 THEN CLI SHALL 直接引用，不做拷贝
8. WHEN 版本冲突（同一包的两个不同版本被间接依赖）THEN CLI SHALL 报错并要求用户显式选择版本（不做自动 semver 解析——保持确定性）
9. WHEN LLM 生成代码 THEN 其 SHALL 可以在 `sa.pkg` 中声明依赖，然后在源码中直接使用依赖包的 `@extern` 函数（无需手写 `@import`）

### Requirement 32: 布局标签校验（v0.5 — 可选类型安全增强）

**User Story**  
作为防御性编程的实践者，虽然 SA 刻意不做类型系统，但我希望有一种**可选的**轻量级机制来防止"把 Dog 指针传给期望 Cat 的函数"这种逻辑错误——在不引入完整类型系统的前提下。

**Acceptance Criteria**
1. WHEN 源码中出现 `#tag NAME = UNIQUE_ID` 声明 THEN Flattener SHALL 记录该标签为一个编译期常量（类似 `#def`，但语义不同）
2. WHEN `alloc` 指令附带可选的 `tag NAME` 后缀 THEN Referee SHALL 在该寄存器的元数据中记录其布局标签：
   ```
   dog = alloc 24 tag Dog       // dog 被标记为 Dog 布局
   cat = alloc 16 tag Cat       // cat 被标记为 Cat 布局
   ```
3. WHEN 函数签名中参数附带可选的 `tag NAME` 注解 THEN Referee SHALL 在调用点校验实参的标签是否匹配：
   ```
   @feed_dog(^d: ptr tag Dog):   // 只接受 Dog 标签的指针
   ```
4. IF 调用点传入的寄存器标签与签名声明不匹配 THEN Referee SHALL 返回 `Trap: TagMismatch`
5. WHEN 标签未声明（`alloc` 不带 `tag`）THEN 该寄存器 SHALL 被视为"无标签"（untagged），可以传给任何函数（向后兼容）
6. WHEN 标签校验被启用 THEN 其 SHALL 为**纯编译期**行为，零运行时开销（标签信息不进入产物）
7. WHEN 标签校验被禁用（`--no-tag-check`）THEN Referee SHALL 跳过所有标签比对（用于性能敏感的场景或向后兼容）
8. WHEN 用户指定 `--strict-tags` THEN 所有 `alloc` 指令 SHALL 必须携带 `tag NAME`，未标记的 `alloc` 直接 `Trap: MissingTag`；此模式用于高可靠性/军工场景，确保零类型混淆
9. **Non-Goal**：标签不是类型系统。不支持继承、不支持泛型标签、不支持标签上的方法。它只是一个"这块内存的布局是什么"的编译期断言

### Requirement 33: Referee 形式化验证（v0.6 — 高可靠性认证）

**User Story**  
作为军工/航空/医疗等高可靠性领域的采用者，我需要数学证明 SA 的 Referee 算法本身没有 Bug——不是靠测试覆盖率，而是靠定理证明器（如 Coq / Lean4 / Isabelle）产出的机器可检查证明。

**Acceptance Criteria**
1. WHEN Referee 的核心状态机逻辑被提取 THEN 其 SHALL 被翻译为 Coq 或 Lean4 的等价规范（Spec），行数 ≤ 1000 行定理证明代码
2. WHEN 形式化规范被建立 THEN 以下性质 SHALL 被证明：
   - **健全性（Soundness）**：若 Referee 放行一段指令流，则该流在任何执行路径上都不会发生 Use-After-Free、Double-Free 或 Memory Leak
   - **完备性（Completeness）**：若一段指令流在所有执行路径上都是内存安全的，则 Referee 不会误报 Trap（无假阳性）
   - **终止性（Termination）**：Referee 对任意有限长度的指令流都会在有限步内产出结果
3. WHEN 证明完成 THEN 其 SHALL 可被 Coq/Lean4 的类型检查器机器验证（不依赖人工审查）
4. WHEN Referee 的 Zig 实现被修改 THEN CI SHALL 要求同步更新形式化规范并重新验证证明（否则阻断合入）
5. WHEN 高可靠性认证（如 DO-178C Level A）被申请 THEN 形式化证明 SHALL 作为"设计保证等级"（Design Assurance Level）的核心证据提交
6. WHEN Referee 被硬件化（FPGA 实现）THEN 形式化规范 SHALL 作为硬件设计的黄金参考（Golden Reference）

---

## 3. MVP 范围与阶段性里程碑

### 阶段一（Week 1-2）：协议定型
- 产出：白皮书 v1.0、EBNF 语法规范、Capability Mask 真值表、≥ 50 条测试用例
- 固化五大操作符（`=` `&` `^` `!` `*`）与 `@ffi_wrapper` / `assume_safe` / `assume_borrow` / `@sys_*` / `@export` / `@extern` 契约
- 冻结 ISA 分组（整数/位/浮点/SIMD/原子）与 `!`/`?` 错误传播协议
- 冻结 `#loc` 源码映射伪指令语法

### 阶段二（Week 3-5）：前端预处理器（Flattener）
- 产出：逐行扫描 Lexer + 宏/REP/EXPAND 展平器 + `#def` 替换器 + 禁用语法扫描器 + `#loc` 收集器
- 约束：零 AST、零作用域树

### 阶段三（Week 6-9）：Referee 验证器
- 产出：Capability Mask 状态机 + JSON Trap 报告（含 `upstream_loc`）+ Gas 报告 + Phi 汇聚检查 + 气闸舱 `IllegalUnsafeContext` / `FfiOwnershipViolation` / `EarlyReturnLeak` 校验 + 原子 ordering 检查
- 约束：核心代码 ≤ 2500 行 Zig（MVP 基线），stretch goal ≤ 1500 行
- **新增一周**：补足真实代码 benchmark 与性能调优（R9.6 要求"真实代码"基准而非合成直线流）

### 阶段四（Week 10-11）：LLVM IR 发射器 + WASM 直出 + CLI
- 产出：
  - 三地址码 → LLVM IR 文本映射表（无 Zig 源码往返）
  - DWARF `!DILocation` 元数据（承载 `upstream_loc`）
  - WASM 二进制手写发射器（wasm32 / wasm64 双目标）+ DWARF-in-WASM 调试段
  - `saasm run` / `build-exe` / `build-wasm` / `build-obj` 四模 CLI
  - `-g` / `--no-debug` 调试信息开关
  - `zig cc` 链接驱动集成

### 阶段五（Week 12）：`@sys_*` 内建原语 + FFI 气闸舱 + 错误传播 runtime
- 产出：
  - Native 下映射到 libc/syscall 的 `@sys_print` / `@sys_read_file` / `@sys_write_file` / `@sys_exit` / `@sys_argv` / `@sys_argc`
  - WASM 下映射到 WASI 导入的同名原语
  - `__sa_panic` 运行时符号（Native stderr + exit，WASM `unreachable`）
  - Rust std 桥接（防波堤）示例工程

### 阶段六（Week 13-14）：LLM Pilot + Hello-Compute + AutoBevy（最低优先级）
- 产出：
  - LLM Pilot 30 题 × 3 模型 baseline 报告（R23.3）
  - AutoBevy 1K 实体冒烟（最低优先级验证）；1M 实体 + Bevy ±30% 留 post-MVP
  - Hello-Compute 样例（`.exe` + `.wasm32` + `.wasm64`）
  - 端到端 CI 流水线
  - GDB / LLDB 上游行号断点验证

**MVP 总计**：约 14 周（单人主导，比上版 +2 周用于真实性能调优、调试信息、LLM pilot）

---

## 4. 非功能性需求

| 维度 | 指标 |
|---|---|
| Referee 单线程吞吐 | ≥ 500K 指令行/秒 (MVP) / ≥ 1M (stretch) |
| 白皮书体积 | ≤ 2000 行 |
| Hello-Compute WASM 体积 | ≤ 48 KB (MVP) / ≤ 32 KB (stretch) |
| Referee 代码行数 | ≤ 2500 行 (MVP) / ≤ 1500 行 (stretch) |
| Flattener + Referee 组合耗时（100 万行指令流） | ≤ 300 ms (MVP) / ≤ 100 ms (stretch) |
| Hello-Compute `.exe` 体积 | ≤ 800 KB (MVP) / ≤ 500 KB (stretch) |
| 测试通过率 | ≥ 99.9% |
| LLM 零训练生成成功率 | **实测 baseline**（R23.3 Pilot 输出，不预设数字） |
| AutoBevy 1K 实体冒烟 | 必须通过（最低优先级验证） |
| AutoBevy 1M 实体 + Bevy ±30% | 最低优先级 post-MVP stretch goal |
| CLI 二进制 | 单文件静态可执行，≤ 15 MB (MVP) / ≤ 10 MB (stretch) |

---

## 5. 风险与假设

### 5.1 风险
- **R1**：LLM 在长序列扁平指令流中仍可能产生偏移量幻觉。缓解：R7 `#def` + R8 宏展平
- **R2**：LLM 对扁平 CFG（`L_` + `jmp/br`）的原生亲和度可能低于嵌套结构。缓解：R23.3 Pilot 实测；R23.4 预留伪嵌套前端讨论位
- **R3**：WASM64 (memory64) runtime 生态仍在演进。缓解：默认 wasm32，`--wasm64` 可选
- **R4**：AutoBevy 1M 性能对标 Bevy 依赖 SIMD + 并行调度 + 缓存布局，12 周难达成。缓解：降级为最低优先级 stretch goal，MVP 只要求 1K 冒烟
- **R5**：直接发射 LLVM IR 需跟随 LLVM 版本升级。缓解：锁定 Zig 内置 LLVM 版本入 CI 矩阵
- **R6**：FFI 气闸舱的 `assume_*` 设计不严谨会变成全局 unsafe 漏洞。缓解：R13.5 Referee O(1) 强制校验
- **R7**：LLVM O3 在中等规模代码库下仍为秒级到十秒级瓶颈；"毫秒级编译"宣传仅对 Debug 成立。缓解：MVP 默认 `saasm build-exe` 走 O1，O3 显式开启
- **R8**：SA 前端降级合约（R20）对上游实现者要求高，新手写 smrustc 会反复踩 Phi 汇聚坑。缓解：R20.8 提供 `libsa_scope` helper 库封装常见作用域跟踪模式
- **R9**：调试信息（R19）实现成本高估可能导致 MVP 交付延期。缓解：DWARF 生成作为 stretch；MVP 至少保证 Trap 报告带 `upstream_loc`

### 5.2 关键假设
- **A1**：目标 LLM 至少具备阅读 2000 行 system prompt 并遵循结构化指令的能力（GPT-4 级别及以上）
- **A2**：开发者具备编译器前端、MIR 设计、Zig、LLVM IR、WASM 二进制格式、DWARF 的交叉经验
- **A3**：工具链使用 Zig（仅作 LLVM 驱动器 + 链接器 + 跨平台 runtime 入口），不依赖 Rust 官方工具链；允许手动构建 Rust std 防波堤作为可选 FFI 扩展
- **A4**：前端（smrustc 或 LLM）承担全部词法作用域跟踪与隐式 Drop 插入责任（R20），SA 永不提供隐式 Drop

---

## 6. 附录：核心符号速查表

| 符号 | 语义 | 状态影响 |
|---|---|---|
| `=` | 分配/绑定 | 目标 → Active |
| `&` | 借用锁定 | 源 → Locked，生成借用 → Active(Borrow) |
| `^` | 消费/Move | 源 → Consumed |
| `!` | 释放 | 借用 → 解锁源；所有权 → 物理 free + Consumed |
| `!`（后缀） | 可失败函数标记 | 返回值变为 `{status, value}` 结构体 |
| `?` | 错误传播 | status ≠ 0 则 early return |
| `*` | 裸指针降级 | 产生无掩码寄存器；仅允许出现在 `@ffi_wrapper` 内 |
| `assume_safe reg` | FFI 受洗（持久所有权） | 裸指针 → Active；仅允许 `@ffi_wrapper` |
| `assume_borrow reg [, mut]` | FFI 受洗（临时借用） | 裸指针 → BorrowView+Locked；仅允许 `@ffi_wrapper` |
| `$...$` | 原生代码嵌入逃逸门 | 内部保守消费所涉寄存器 |
| `@name` | 函数声明/调用 | — |
| `@ffi_wrapper name` | 气闸舱函数 | 唯一允许 `*` / `assume_*` 的作用域 |
| `@extern name` | 外部符号声明（C-ABI） | 产出 LLVM `declare` / WASM `import` |
| `@export name` | 对外导出函数（无名称修饰） | 产出标准 C-ABI 符号 |
| `@sys_*` | 内建系统原语 | Native ↔ WASI 自动双轨降级 |
| `@const NAME = ...` | 全局只读常量数据（rodata，无类型标注） | 永续 Immutable 寄存器，禁止 `^` / `!` / 独占借用 |
| `panic(code)` | 不可恢复错误（无消息） | Native `__sa_panic(code,0,0)` / WASM `unreachable` |
| `panic_msg(code, *s, len)` | 不可恢复错误（含消息） | Native 写 stderr 再 `_exit`；WASM `fd_write`+`unreachable` |
| `stack_alloc N` | 栈分配（函数内） | 生命周期绑定函数出口；禁止 `^` 移出 |
| `ptr_add base, off` | 裸指针算术 | 普通函数内可从借用派生 `InteriorPtr` |
| `atomic_rmw_<OP>` | 原子读改写 | `add/sub/and/or/xor/xchg/min/max/umin/umax` |
| `#mode compact` | 启用中缀糖（v0.2 可选） | 仅允许 8 条白名单中缀，预处理期展开 |
| `#def NAME = VAL` | 常量字典 | 预处理期纯文本替换 |
| `#loc "file":line:col` | 上游位置伪指令 | 下一条指令携带 upstream_loc |
| `[MACRO]...[END_MACRO]` | 宏定义 | 预处理期展平 |
| `[REP N]...[END_REP]` | 编译期展开循环 | 预处理期展平 |
| `EXPAND NAME args` | 宏调用 | 预处理期展平 |
| `L_LABEL:` | 跳转标签 | Phi 汇聚点校验触发 |
| `jmp` / `br` / `br_null` | 跳转指令 | 控制流切换 |
| `atomic_load` / `atomic_store` / `cmpxchg` / `fence` | 原子原语 | ordering 参数参与校验 |

---

**文档终态：以上 33 条 Requirements（R1–R24 MVP + R25–R27 v0.3 + R28–R30 v0.4 + R31–R32 v0.5 + R33 v0.6）为 SA 实现的强约束契约。任何后续 Design 阶段不得弱化或绕过已有特性。**
