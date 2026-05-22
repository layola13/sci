# SA 语言与编译器 需求文档

## 1. 项目概述

### 1.1 项目代号
**SA** (Symbolic Affine) — 符号化仿射语言。实现与工具链保留 `sa` 作为命令行前缀，但文件扩展名统一为 `.sa` / `.sai` / `.sal`。

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
6. WHEN CLI 提供 `sa layout` 子命令 THEN 其 SHALL 接受结构体字段描述（名称 + 类型），自动计算对齐与偏移量，输出标准 `#def` 字典文本（见 R7b）

### Requirement 7b: `sa layout` 布局生成工具（v0.1 辅助工具）

**User Story**  
作为 LLM 或人类开发者，手算复杂结构体的字节偏移量（尤其是混合 `i32` / `f64` 时的对齐填充）极易出错。我需要一个 CLI 工具，输入字段描述，自动输出正确的 `#def` 字典。

**Acceptance Criteria**
1. WHEN 用户执行 `sa layout --name Entity --fields "id:u32, pos_x:f64, pos_y:f64, hp:i32"` THEN CLI SHALL 输出：
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
6. WHEN LLM 调用此工具 THEN 其 SHALL 可以直接把输出粘贴到 `.sa` 文件顶部使用，无需任何修改
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
1. WHEN 完整工具链被调用 THEN `.sa → .wasm` 端到端流程 SHALL 输出单一 `.wasm` 文件，不经过任何 Zig 源码往返
2. WHEN `.wasm` 被加载 THEN 其导出符号 SHALL 完全兼容 WASI / 标准 C-ABI
3. WHEN 简单 Hello-Compute 样例编译完成 THEN 其 `.wasm` 体积 SHALL ≤ 32 KB
4. WHEN 运行在支持 memory64 的 runtime（如 Wasmtime/Wasmer 最新版）THEN 其 SHALL 能寻址 > 4 GB 堆内存
5. WHEN `@sys_*` 内建原语在 WASM 目标下编译 THEN 其 SHALL 被映射为 WASI 导入（`fd_read` / `fd_write` 等）；若目标环境不支持 WASI THEN 编译器 SHALL 在发射前拒绝并报错

### Requirement 16: CLI 三模驱动（run / build-exe / build-wasm）

**User Story**  
作为开发者或 LLM，我需要像 `bun` / `deno` 那样一行命令就能跑通 SA 源码，或者打包成跨平台独立可执行文件，或者降级为沙盒 WASM，而不需要配置任何外部工具链。

**Acceptance Criteria**
1. WHEN 用户执行 `sa run <file.sa> [args...]` THEN CLI SHALL 走完 Flattener + Referee + 内存解释器/JIT，直接在本进程内执行 SA 代码，拥有宿主操作系统权限（文件读写、终端打印、进程退出码）
2. WHEN 用户执行 `sa build-exe <file.sa> [-o out]` THEN CLI SHALL 依次运行 Flattener + Referee + LLVM IR 发射器 + `zig cc` 链接器，产出当前平台的独立原生可执行文件
3. WHEN 用户执行 `sa build-wasm <file.sa> [-o out.wasm]` THEN CLI SHALL 依次运行 Flattener + Referee + WASM 二进制发射器，产出 `.wasm` 文件（wasm32 或 wasm64 由 `--target` 参数控制）
4. WHEN 用户执行 `sa build-obj <file.sa> -o out.o` THEN CLI SHALL 产出可被任意 C/C++/Rust 工程链接的标准目标文件
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
5. WHEN 用户调用 `sa build-exe -g` THEN 产物 SHALL 在 GDB / LLDB 中能以上游文件名 + 行号做断点与单步
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
4. WHEN `libsa_async` 被分发 THEN 其 SHALL 以 `.sa` 文本文件形式提供（可被 `@import` 或 Flattener 的文件拼接机制引入），不依赖任何 C-ABI 库
5. WHEN 前端不使用 `libsa_async` THEN 其 SHALL 仍可手写等价的 SA 代码（宏是便利，不是强制）
6. **Non-Goal**：SA 语法层不引入 `@async` / `await_state` 等新关键字；不引入隐式展开；不引入跨 await 变量的自动存取推导

### Requirement 27: 发射产物诊断级别（v0.3）

**User Story**  
作为部署方，我需要明确 SA 编译产物在不同构建模式下的安全保障级别，以便在性能与安全之间做出知情选择。

**Acceptance Criteria**
1. WHEN 用户执行 `sa build-exe` 或 `sa build-wasm`（默认 `--release`）THEN 产物 SHALL 不包含任何 Referee 运行时代码；所有所有权校验已在编译期完成，Release 产物零运行时开销
2. WHEN 用户指定 `--debug-gas` THEN 产物 SHALL 在每个函数入口/基本块头部插入 gas 计数器自增指令；超过 `gas_set_limit` 阈值时触发 `Trap: GasExceeded`（R11.4 的运行时实现）
3. WHEN 用户指定 `--debug-san` THEN 产物 SHALL 在 `alloc` / `!free` 点插入红黑树/哈希表簿记，用于运行期侦测 Use-After-Free 和 Double-Free（类似 ASAN 的轻量版）；此模式下性能损耗预期 2-5x
4. WHEN `--debug-san` 检测到 UAF/Double-Free THEN 其 SHALL 输出结构化 JSON 报告（含 `upstream_loc`），格式与 Referee 的 Trap 报告一致
5. WHEN `--release` 模式下发生段错误 THEN 其 SHALL 不是 SA 的责任——这意味着前端降级合约（R20）被违反，或 FFI 气闸舱外的宿主代码有 bug
6. WHEN 三种模式被文档化 THEN 白皮书 SHALL 在"构建模式"章节明确说明各模式的安全保障边界与性能代价

---

### Requirement 28: 接口契约文件 `.sai`（v0.4 — 并行开发基建）

**User Story**  
作为多人/多 LLM 并行开发同一 APP 的协作者，我需要一种轻量级的接口契约文件，使得 A 和 B 可以同时开发不同模块，互不阻塞，只要接口文件先冻结即可。

**Acceptance Criteria**
1. WHEN 开发者创建 `module.sai` 文件 THEN 其 SHALL 仅包含 `@extern` 函数签名声明（含 `cap_prefix` + `ty` + 返回类型 + `!` 后缀），不包含函数体
2. WHEN 另一个 `.sa` 文件通过 `@import "module.sai"` 引入接口 THEN Flattener SHALL 将其中的 `@extern` 声明注入当前编译单元
3. WHEN Referee 校验调用点 THEN 其 SHALL 使用 `.sai` 中声明的签名 tuple 做 `CapabilityMismatch` 校验，**无需**实际函数体存在
4. WHEN 接口文件与实现文件的签名不一致 THEN 链接期（`zig cc`）SHALL 报 symbol type mismatch 错误；Referee 层面在各自编译单元内独立通过
5. WHEN 多个 `.sa` 文件引用同一 `.sai` THEN 它们 SHALL 可以被**完全并行**编译（各自独立跑 Flattener + Referee + Emitter），最后一步链接合并
6. WHEN `.sai` 文件被修改 THEN CI SHALL 自动检测哪些依赖方需要重新验证（通过文件哈希比对）
7. WHEN 接口文件包含所有权语义注释 THEN 其 SHALL 支持可选的 `// @contract: consumes data` 风格注释（纯文档性质，Referee 不解析，但 `libsa_scope` helper 可读取）

### Requirement 29: 版本化布局文件 `.sal`（v0.4 — 并行开发基建）

**User Story**  
作为多人协作团队，共享数据结构的内存布局（如 Entity / Component / Message）是最常见的冲突源。我需要一种版本化的布局声明文件，使布局变更可追踪、可检测。

**Acceptance Criteria**
1. WHEN 团队创建 `entity.sal` 文件 THEN 其 SHALL 仅包含 `#def` 常量声明 + 一个 `#version N` 元数据行
2. WHEN `.sa` 文件通过 `@import "entity.sal"` 引入布局 THEN Flattener SHALL 记录该文件引用的 `#version` 值
3. WHEN 布局文件的 `#version` 递增 THEN CI SHALL 自动扫描所有引用方，标记为"需要重新验证"
4. WHEN 两个 `.sa` 文件引用了同一布局文件的**不同版本** THEN 链接期 SHALL 报 `Trap: LayoutVersionConflict`（通过在 `.o` 文件中嵌入版本元数据实现）
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
1. WHEN `sa build-obj` 被调用 THEN 其 SHALL 支持 `--incremental` 模式：按函数粒度产出独立的 `.o` 文件（每个函数一个 `.o`）
2. WHEN 源文件中某个函数未修改（通过函数体哈希比对）THEN 增量模式 SHALL 跳过该函数的 Emitter + zig cc 阶段，直接复用上次的 `.o`
3. WHEN 增量模式被启用 THEN 最终链接 SHALL 把所有函数的 `.o` 合并为单一产物
4. WHEN 函数之间无跨函数分析依赖（SA 的设计保证）THEN 增量编译的正确性 SHALL 不依赖编译顺序
5. WHEN 增量缓存目录 THEN 其 SHALL 位于 `.sa-cache/` 下，按函数名哈希组织
6. WHEN `--incremental` 与 `--debug-san` 同时启用 THEN 每个函数的 `.o` SHALL 独立包含 sanitizer 簿记入口（不依赖全局状态）

---

### Requirement 31: 零信任包管理 `sa.mod` / `sa.lock` / `sa.sum`（v0.5 — 生态基建）

**User Story**  
作为 LLM 或人类开发者，当项目规模增长到多文件/多模块时，我需要一种**去中心化、绝对确定性、零信任**的依赖管理机制，使得"引入别人写的 SA 库"像 `go get` 一样简单，而不是手动拷贝 `.sa` 文件，**也不必承担 npm/crates.io 式的供应链投毒、SemVer 求解地狱与黑盒二进制风险**。

> 本需求遵循 **去中心化（URL 即命名空间）**、**绝对哈希钉版（无 SemVer 求解）**、**纯文本源码分发（拒绝预编译二进制）**、**默认零权限**、**零隐式状态** 五条物理级原则。详细设计文档见 [`docs/package_management.md`](../../../docs/package_management.md)。

**Acceptance Criteria**
1. WHEN 项目根目录存在 `sa.mod` 文件 THEN CLI SHALL 识别其为依赖清单，每条依赖为单行扁平声明，格式为：
   ```
   require <URL> @<ref> sha256:<hash> [grants [<cap>, ...]]
   ```
   字段：
   - URL：完整命名空间（如 `github.com/xiaoming/sa-ecs` / `gitlab.corp.local/team/util`）
   - `@<ref>`：Git tag / branch / commit
   - `sha256:`：纯文本源码 SHA-256 哈希
   - `grants`：可选权限白名单，缺省 = `grants []`（绝对零权限）
2. WHEN `sa build-exe` / `build-wasm` / `build-obj` 被调用 THEN CLI SHALL 解析 `sa.mod`，按 URL 拓扑序定位 / 拉取依赖，并对每个依赖独立跑 Flattener + Referee + Emitter
3. WHEN 依赖包内的 `.sai` 接口文件存在 THEN 其 SHALL 被自动注入当前编译单元（等价于 `@import`）
4. WHEN 依赖包内的 `.sal` 布局文件存在 THEN 其 `#def` 常量 SHALL 被自动注入（带命名空间前缀避免冲突：`pkg_url.FIELD_NAME`）
5. WHEN 两个依赖包声明了同名 `@export` 函数 THEN 链接期 SHALL 报 `Trap: DuplicateExportSymbol`
6. WHEN 拉取源码字节级 SHA-256 与 `sa.mod` 中 `sha256:` 字段不一致 THEN 编译器 SHALL 立刻 `Fatal Error: UpstreamShaMismatch`，**绝不**重新解析或推导
7. WHEN 同一包的两个不同版本被间接依赖 THEN CLI SHALL 报错并要求用户显式声明（不做自动 semver 求解 —— 保持确定性，杜绝依赖地狱）
8. WHEN 项目存在 `sa.sum` 文件 THEN CLI SHALL 把全部传递依赖的哈希拍平记录其中；任意子树包源码变化 → 顶层 `sa.sum` 哈希不匹配 → 整棵树物理熔断
9. WHEN LLM 生成代码 THEN 其 SHALL 可以在 `sa.mod` 中声明依赖，然后在源码中直接使用依赖包的 `@extern` 函数（无需手写 `@import`）
10. **Non-Goal**：
    - 不建造 crates.io / npm 式的中心化注册仓库
    - 不实现任何 SemVer 兼容性 SAT 求解
    - 不分发预编译二进制（`.so` / `.dll` / `.a` / wheels）
    - 不引入 `postinstall` 等任何生命周期钩子（`sa fetch` 必须图灵不完备）

### Requirement 31a: 默认局部 + 可选全局缓存（v0.5）

**User Story**  
作为开发者，我希望默认拉到的依赖位于当前项目目录内（自包含、可断网拷贝部署），但允许我在熟悉风险后通过显式 CLI 参数复用全局缓存以节省磁盘。

**Acceptance Criteria**
1. WHEN `sa fetch`（无参数）被调用 THEN CLI SHALL 把依赖拉到当前项目根目录的 `sa_vendor/<URL>/`
2. WHEN `sa fetch -g`（带 `-g` 参数）被调用 THEN CLI SHALL 拉取到全局缓存 `~/.sa/pkg/<URL>@<ref>/`，且以**只读**形式解压
3. WHEN 编译器解析 `@import` THEN 其 SHALL 严格按以下顺序短路：
   - 项目级 `./sa_vendor/<URL>/`
   - 全局缓存 `~/.sa/pkg/<URL>@<ref>/`
   - 都不存在 → `Trap: PackageNotResolved`
4. WHEN 多个项目依赖同一全局缓存的库 THEN 编译器 SHALL 通过 `mmap` 内存映射只读读取（同源不复制）
5. WHEN `sa.mod` 被提交到 Git THEN 其 SHALL **不**记录"开发者用全局还是局部"的偏好（这是 CLI 个人操作自由，团队成员可异构）
6. WHEN 项目被拷贝到任意机器（包括离线/无管理员权限环境） THEN 只要拷贝带上 `sa_vendor/` + `sa.mod` + `sa.lock`，`sa build --offline` SHALL 完整可用
7. **Non-Goal**：禁止依赖任何全局配置文件（如 `~/.sa/config.toml`、`~/.sa/mirror.toml`）—— 隐式状态会污染编译可重复性，详见 R31g.4

### Requirement 31b: 哑拉取 + 防投毒四道防火墙（v0.5）

**User Story**  
作为安全敏感的开发者，我希望包管理器在物理层面就免疫 npm 式投毒（event-stream / colors.js 等灾难），不需要靠运行扫描工具救火。

**Acceptance Criteria**
1. WHEN `sa fetch <URL>` 被调用 THEN CLI SHALL 仅执行纯 HTTP/Git 文本下载与解压，**不执行**任何来自被拉取包的代码（无 hooks / scripts / postinstall / build.zig / setup.py）
2. WHEN 任意被拉取的包源码内容字节变更 THEN 其 SHA-256 SHALL 必然变化；编译器据此熔断，杜绝"被覆盖 tag"式的隐式更新（npm 死穴 1：SemVer 自动升级）
3. WHEN 编译器扫描到 `sa.mod` 中的 URL THEN 其 SHALL 直接对应一个 Git host 物理坐标，**不允许**任何"短名称→注册中心查表"的中间层（解决 npm 死穴 2：typosquatting 抢注）
4. WHEN 任意依赖包以 `.so` / `.dll` / `.dylib` / `.a` / `.lib` / `.whl` / `.node` 等编译产物形态分发 THEN CLI SHALL 拒绝拉取，报 `Trap: PrecompiledArtifactRejected`（解决 npm 死穴 3：二进制黑盒）
5. WHEN 项目存在 `sa.sum` 文件且代表全树拍平的哈希 THEN 任意传递依赖（A 依赖 B，B 依赖 C）的字节变化 SHALL 触发顶层哈希失配并物理熔断（防御传递依赖投毒）

### Requirement 31c: 模块级零权限沙箱（v0.5）

**User Story**  
作为企业安全主管，我需要一个比 Deno `--allow-net` 更精细的权限模型 —— 把权限收敛到**单个第三方包级别**，让主程序拥有网络权也无法让"字符串处理工具包"间接联网。

**Acceptance Criteria**
1. WHEN `sa.mod` 中某依赖未显式写 `grants [...]` THEN 该依赖 SHALL 被赋予**绝对零权限**（不能调用任何 `@sys_*` 原语）
2. WHEN `sa.mod` 中某依赖写了 `grants [net_tx]` THEN 该依赖 SHALL **仅**能调用 `@sys_net_tx`，调用列表外原语立刻熔断
3. WHEN 编译器扫描某依赖包源码 AST 发现 `@sys_*` 调用 THEN 其 SHALL 通过物理路径（如 `sa_vendor/github.com/.../`）反推所属包，与 `sa.mod` 的 `grants` 列表精确匹配
4. IF 包内 `@sys_*` 调用未被该包的 `grants` 覆盖 THEN 编译器 SHALL 拒绝生成机器码，返回 `Trap: UnauthorizedPrimitive`，并在错误中打印：
   - 越权原语名（如 `@sys_net_tx`）
   - 调用所在源码位置（`upstream_loc`）
   - 当前 `grants` 列表（可能为空）
5. WHEN 零权限包 A 调用了高权限包 B 的公开函数（间接复用 B 的网络权）THEN 编译器 SHALL 在控制流分析阶段拒绝跨包能力提升，返回 `Trap: NonTransitivePrimitive`
6. WHEN 标签校验启用 THEN 权限校验 SHALL 与 R32 标签校验互不依赖（独立通路）
7. **Non-Goal**：进程级 `--allow-net` 风格的全局权限授予（粒度太粗，违反"模块级微沙箱"原则）

### Requirement 31d: AST X 光扫描与安全信用评分（v0.5）

**User Story**  
作为开发者，我希望在 `sa fetch` 落盘的瞬间就能在终端看到这个包"想要哪些权限"的体检报告，不必再靠 Snyk 这类外部静态扫描工具来事后救火。

**Acceptance Criteria**
1. WHEN `sa fetch <URL>` 完成源码落盘 THEN CLI SHALL 在几毫秒内（≤ 50ms 单包）跑一次单遍 AST 扫描，搜剿全部 `@sys_*` 原语调用，并打印结构化报告至 stdout
2. WHEN 报告生成 THEN 其 SHALL 计算"信用分"（Trust Score，0–100）：
   - 100：无任何 `@sys_*` 调用（Pure Compute）
   - 80：仅 `@sys_mem_*`
   - 50：含 `@sys_io_*`（本地文件读写）
   - 20 及以下：含 `@sys_net_*` 或跨核心绑定
3. WHEN 报告输出 THEN 其 SHALL 至少包含：
   - 包 URL + 版本 + 源码 SHA
   - 全部 `@sys_*` 调用列表 + 每条的 `upstream_loc`
   - Trust Score 数值与等级（HIGH RISK / MEDIUM / SAFE）
   - 当前在 `sa.mod` 中的 `grants` 状态
   - 修复建议（手动添加 `grants [...]` 的字符串模板）
4. WHEN `sa audit <URL>` 被调用 THEN 其 SHALL 重新跑一次扫描并打印同样格式报告（用于代码审查时引用）
5. WHEN 报告输出 THEN 其 SHALL 支持 `--format json` 输出结构化 JSON，便于 CI 收集 / GitHub Step Summary 集成
6. **Non-Goal**：不依赖 LLM / SAT solver，纯静态 AST 词法扫描；不引入"沙箱运行后取行为"等动态分析

### Requirement 31e: 破窗确权 —— 强制人肉审判台（v0.5）

**User Story**  
作为开发者，我希望在面对低分高危依赖时，工具不要静默通过、也不要粗暴删源码（剥夺我的数字主权），而是通过**极致的交互摩擦**逼我清醒确认 / 主动净化依赖树。

**Acceptance Criteria**
1. WHEN 编译器在内存中检测到某依赖既包含未授权的 `@sys_*` 原语，又信用分 ≤ 20 THEN 其 SHALL 把该依赖临时标记为 `BLOCKED_RISK`（仅存当前进程内存）并阻塞编译管线
2. WHEN 阻塞触发 THEN CLI SHALL 在 stdout 打印审判台 banner，包含：
   - 醒目的 `[SA-CRITICAL WARNING] RISK ACKNOWLEDGMENT REQUIRED` 标题
   - 完整的越权权限列表（带 `upstream_loc`）
   - 信用分
   - 提示输入完整 URL 才能解锁
3. WHEN CLI 等待输入 THEN 其 SHALL **仅**接受**完整匹配**的 URL 字符串（如 `github.com/hacker/bad-lib`）
   - 不接受 `y` / `n` / 简写
   - 不接受任何裁剪或前缀
4. WHEN `std.os.isatty(stdin) == false` THEN CLI SHALL **拒绝**等待输入，立刻报 `Trap: MissingTtyForConfirmation` 并以非零状态码退出（防止 `yes |` 管道绕过）
5. WHEN 用户输入完整 URL 通过 THEN 编译器 SHALL **仅在当前进程内存中**标记为已确权，**绝不**写入任何文件（`sa.mod` / `sa.lock` / 全局配置 / 项目本地配置都不允许）
6. WHEN 进程退出（不论编译成功还是失败） THEN 该确权状态 SHALL 随 allocator 释放在物理内存中彻底蒸发；下次编译必须重新人肉输入
7. WHEN 任意依赖触发 `BLOCKED_RISK` THEN CLI SHALL 拒绝以 `--yes` / `--auto-approve` 等任何"绕过参数"在 TTY 模式下跳过审判
8. **Non-Goal**：不允许"永久豁免"（写入 `sa.mod` 会通过 Git 横向传播形成后门）；不允许进程级缓存（违反每次必输的摩擦原则）

### Requirement 31f: 指令级哈希钉版与项目级孤岛（v0.5）

**User Story**  
作为零信任架构的实践者，我不信任易变的源码（黑客可加几行宏混淆），我只信任**这一刻被本项目编译出来的、那段唯一确定的物理机器码**。

**Acceptance Criteria**
1. WHEN 开发者通过 R31e 的审判台确认某依赖 THEN 编译器 SHALL 立刻把该依赖单独送入编译管线，生成 SA-ASM 机器码 / WASM 二进制块
2. WHEN 机器码生成 THEN 编译器 SHALL 计算 SHA-256，并写入**当前项目根**的 `sa.lock`：
   ```
   dependency "github.com/hacker/bad-lib" {
       version: "v1.2.0"
       source_sha:                "8f4e2d..."
       approved_machine_code_hash: "a1b2c3..."
   }
   ```
3. WHEN 下次 `sa build` 重新扫描该依赖 THEN 编译器 SHALL 在内存中重新生成机器码，与 `sa.lock` 的 `approved_machine_code_hash` 逐比特比对：
   - 一致 → 跳过审判台直接放行（增量 AOT 红利）
   - 不一致 → 视为新风险，重弹审判台
4. WHEN `sa.lock` 被生成 THEN 其 SHALL **绝对**仅存储于**当前项目根**目录，不允许全局或父目录复用
5. WHEN 项目编译产物缓存（如 `.samx` / `.o`） THEN 其 SHALL 存储于当前项目的 `.sa_cache/`，**不可**与其他项目共享
6. WHEN 同一台机器上两个项目都依赖同一高危包 THEN 两个项目的开发者 SHALL **各自**面对一次审判台、**各自**输入 URL、**各自**生成物理隔离的 `sa.lock` 与机器码缓存（信任不跨项目漂移）
7. WHEN 全平台交叉编译启用（`sa build --all-targets --lock-only`） THEN 编译器 SHALL 在内存中同时推导 `x86_64-linux-musl` / `x86_64-windows-gnu` / `aarch64-macos` / `wasm32-wasi` 等目标的机器码哈希并并行写入 `sa.lock`
8. **Non-Goal**：禁止全局机器码缓存（信任污染：爬虫项目的网络权机器码 → 钱包项目可能被无声击穿）；禁止跨项目复用 `approved_machine_code_hash`

### Requirement 31g: CI/CD 双轨执行 + 内网/断网模式（v0.5）

**User Story**  
作为团队 / 企业用户，我希望 SA 既能在本地终端做"严格人肉摩擦"，又能在 GitHub Actions 这种无 TTY 流水线、甚至完全断网的内网 CI 环境里安全自动化。

**Acceptance Criteria**
1. WHEN 编译器探测到以下任一信号 THEN 其 SHALL 自动进入 CI 模式：
   - 环境变量 `CI=true` 或 `GITHUB_ACTIONS=true`
   - `std.os.isatty(stdin) == false`
   - 显式 flag `sa build --ci`
2. WHEN CI 模式启用且检测到未审计高危依赖 THEN 其 SHALL 按以下两种策略二选一执行（由 CLI 参数显式选择）：
   - **冷酷熔断（默认）**：打印权限列表 → 退出码 1 → 流水线爆红
   - **染色放行**（`--allow-unaudited-risks`）：照常输出二进制，但产物元数据段写入 `TAINTED_UNAUDITED_CODE` 标记，编译日志输出醒目 ASCII 警告 banner，并向 `$GITHUB_STEP_SUMMARY` 写入"高风险资产看板"
3. WHEN CI 编译每个依赖 THEN 其 SHALL 跑双轨核验：
   - **第一轨**：依赖中调用的 `@sys_*` 必须被 `sa.mod` 的 `grants` 覆盖（R31c）
   - **第二轨**：依赖源码字节 SHA == `sa.mod` 中 `sha256:`（R31.6）
   - 任一不满足 → 拒绝产出机器码，分别报 `Trap: UnauthorizedPrimitive` / `Trap: UpstreamShaMismatch`
4. WHEN `sa build --offline` 被调用 THEN 编译器 SHALL **完全切断**网络模块，仅读硬盘 `sa_vendor/`，与 `sa.lock` / `sa.sum` 做物理比对；任何尝试发起网络请求 SHALL 被立即拦截
5. WHEN 内网部署需要 URL 镜像劫持 THEN 编译器 SHALL **仅**支持以下两种来源（按优先级）：
   - 进程级环境变量 `SA_MIRROR_<HOST_UPPER>`（如 `SA_MIRROR_GITHUB_COM=gitlab.corp.local/mirror`）
   - 项目本地 `.sa_env` 文件 或 `sa.mod` 内的 `[mirrors]` 块
6. WHEN 编译器探测到任何全局配置文件（如 `~/.sa/mirror.toml` / `~/.sa/config.toml` / `/etc/sa/*.toml`） THEN 其 SHALL 报 `Trap: ForbiddenGlobalConfig` 并拒绝启动
7. WHEN 染色产物被 Referee runtime 加载 THEN 其 SHALL 在 `main()` 入口前向 stderr 强行打印三行红字 `TAINTED` 警告（无法被 `--release` 移除）
8. WHEN 全平台 CI 矩阵启动（Ubuntu / Windows / macOS Runner 并发） THEN 三平台的 SA 编译器 SHALL 各自计算源码 SHA 与 `sa.mod` 比对（信任锚点是平台无关的源码哈希，机器码哈希仅当 `--lock-only` 时才被本地铸造）
9. **Non-Goal**：CI 模式下不引入 TTY 模拟器（任何"伪交互"都是后门）；不强制要求 GPG/SSH 签名（保留至 v0.6+ 可选模式以兼顾门槛）

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
  - `sa run` / `build-exe` / `build-wasm` / `build-obj` 四模 CLI
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
- **R7**：LLVM O3 在中等规模代码库下仍为秒级到十秒级瓶颈；"毫秒级编译"宣传仅对 Debug 成立。缓解：MVP 默认 `sa build-exe` 走 O1，O3 显式开启
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

### Requirement 34: SA 零信任列式数据库（v0.6 — 数据库生态）

**User Story**  
作为 SA 生态的数据层，我需要一个与包管理同构的列式数据库引擎，支持预编译查询、SHA-256 锁版、模块级权限隔离、零拷贝沙箱执行。

**Acceptance Criteria**

1. WHEN 表 schema 定义为 `.sadb-schema` 文件 THEN 编译器 SHALL 在编译期一次扫描映射为 `#def COL_*_STRIDE` 与 `#def TABLE_*_ROW_BYTES` 常量，生成 `.sai` 接口文件供查询模块导入
2. WHEN 查询模块定义为 `.query.sa` 文件 THEN 编译器 SHALL 编译为二进制 `.qmod` 模块，计算源码 SHA-256 哈希，注册到查询模块注册表
3. WHEN 查询模块声明 `grants [db_read:<table>, db_write:<table>, db_atomic_cursor:<table>, db_alloc_blob:<arena>]` THEN Referee 扩展 SHALL 在注册时执行 X 光扫描，校验所有 `load` / `store` / `atomic_rmw_*` 指令是否在权限白名单内，违规返回 `Trap: DbCapabilityEscalation`
4. WHEN 数据库引擎执行查询模块 THEN 引擎 SHALL 通过 `@ffi_wrapper` 注入列基址为 mmap 只读切片（`MAP_PRIVATE | PROT_READ`），任何越权写入触发 CPU SIGSEGV，宿主进程捕获中断返回 `Trap: DbMemoryGuardViolation`
5. WHEN 表执行 Insert 操作 THEN 引擎 SHALL 用 `atomic_rmw_add global_len, 1` 无锁自增行游标，所有 Insert 竞争此单点串行化点，保证行号唯一分配
6. WHEN 表执行 Blob 分配 THEN 引擎 SHALL 采用 Bump Allocator（纯追加），整段 mmap 视为单个 `alloc`，单次 `!arena` 释放，删除标记墓碑，段死亡比例 ≥ 50% 时触发整段重写
7. WHEN 表数据分层 THEN 引擎 SHALL 支持冷热分层：RAM（7 天）/ mmap NVMe（1 月）/ Zstd 压缩落 S3（1 年+，体积压至 10–15%）
8. WHEN 数据库引擎启动 THEN 引擎 SHALL 不使用 WAL，改用快照 epoch + 不可变段 + 原子游标的等价方案保证崩溃恢复
9. WHEN 跨行事务需要一致性 THEN 引擎 SHALL 支持可选乐观锁（每行 8 字节 version 列，`cmpxchg` 失败返回 `Trap: DbConcurrencyConflict`），明确否决 MVCC
10. WHEN 表 schema 与查询模块分发 THEN 引擎 SHALL 复用 `sa.mod` 的 SHA-256 锁版、零权限默认、URL 即命名空间的包管理哲学，无需单独 `sadb.mod` 文件
11. WHEN CLI 提供数据库子命令 THEN 引擎 SHALL 支持至少 10 条子命令：`db init` / `db register` / `db exec` / `db ingest` / `db snapshot` / `db restore` / `db inspect` / `db compact` / `db lock` / `db verify`
12. WHEN 数据库引擎报错 THEN 引擎 SHALL 登记 12 条新 Trap 错误码（`DbCapabilityEscalation` / `DbMemoryGuardViolation` / `DbBlobArenaOOM` / `DbConcurrencyConflict` / `DbSchemaMismatch` / `DbCursorOverflow` / `DbColumnTypeMismatch` / `DbQueryHashUnknown` / `DbBlobHandleInvalid` / `DbSnapshotCorrupted` / `DbDuplicateRegister` / `DbForbiddenSqlString`），每条附带诊断字段（`table` / `sha256` / `offset` / `expected_mask` / `actual_mask` / `upstream_loc`）

**设计文档**：见 `docs/database.md`（§0–§15 + 附录 A/B）

**决策来源**：talk.md L3859–4848（14 轮数据库脑暴）

---

### Requirement 35: SA 极速网络引擎 `sa_netx`（v0.8 — 物理打败魔法的网络基座）

**User Story**  
作为 SA 生态的网络层，我需要一个能在内网裸跑、单机暴打 Bun/Node/Go 的 io_uring 网络引擎，复用 SA-ASM 的线性所有权与 SA 数据库的算子内核，把"Web 框架"还原为"网络字节流到内存切片的翻译器"。

**Acceptance Criteria**

1. WHEN 网络引擎启动 THEN 引擎 SHALL 在 `src/runtime/sa_net_uring.zig` 提供独立模块，与 `src/runtime/sa_std.zig` 并列存在，导出符号统一以 `sa_netx_` 前缀，**不修改现有 117 个 `sa_*` export，不取代现有 `sa_net_tcp_*` API**
2. WHEN 网络引擎初始化 THEN 引擎 SHALL 通过 `mmap(MAP_POPULATE | MAP_HUGETLB)` 一次性预分配 10⁵ – 10⁶ 个 `ConnectionSlot`（cache-line 对齐 64 字节，含 4 KB inline scratch + overflow 链 + 状态枚举），稳态运行禁止任何 `malloc/free`
3. WHEN 网络引擎处理 I/O THEN 引擎 SHALL 使用 Linux `io_uring`（Zig `std.os.linux.IoUring`），通过 `IORING_OP_ACCEPT_MULTISHOT` + `IORING_OP_RECV_MULTISHOT` + `IORING_REGISTER_PBUF_RING` 实现 per-core sharded reactor，绑核运行（`sched_setaffinity`），**禁用 `epoll` 路径**
4. WHEN 协议拆包 THEN HTTP/1.1 DFA 解析与 WebSocket 帧头解析、SIMD 解掩码 SHALL 全部在 Zig 侧用 `@Vector(16/32, u8)` 完成；**SA-ASM ISA 不新增向量算子，不引入 `bitcast` 指令**，SA-ASM 仅消费结构化 `Ticket`
5. WHEN 网络核心与 SA 业务核心通信 THEN 引擎 SHALL 提供 per-core sharded SPSC 三环（Inbound / Execution / Outbound），每对 reactor↔SA-core 一组独立 SPSC；现有 `sa_std/sync/mpsc.sa` 仅作跨分片回收的慢路径
6. WHEN WebSocket 协议升级 THEN 引擎 SHALL 在原 `ConnectionSlot` 上拨转 `state` 字段（`Http → WebSocket`），fd 与 buffer 不迁移、不分配新内存；握手栈上完成 `Base64(SHA1(key + magic))`
7. WHEN 服务器执行广播扇出（1 source → N receivers，且 `N ≥ 8` 或 `payload ≥ 1.5 KB`）THEN 引擎 SHALL 通过 `IORING_OP_SEND_ZC` + 共享物理切片 + 引用计数（`gen` 代纪元）+ `notification CQE` 回收实现内核 DMA 扇出；**单点小包通信走 `IORING_OP_SEND` + provided buffer**，禁止对小消息默认启用 SEND_ZC
8. WHEN 入站环满 THEN reactor SHALL 停止 arm `IORING_OP_RECV_MULTISHOT`，让 TCP 滑动窗口自然收窄，**绝不丢包，绝不分配新 buffer**；出站环满时 `sa_netx_push_outbound` 返回 `EAGAIN`，由业务决定丢弃
9. WHEN 连接闲置或握手超时 THEN 引擎 SHALL 通过 `IORING_OP_TIMEOUT` 配对清扫，关闭后槽位归还连接池；连接生命周期严格走九态状态机（`Free / Accepting / Handshake / Reading / Http / WebSocket / RawBinary / HalfClosed / Closing`）
10. WHEN SA-ASM 业务调用网络 FFI THEN 引擎 SHALL 提供 7 条新 `@extern`：`sa_netx_init` / `sa_netx_listen` / `sa_netx_recv_ticket` / `sa_netx_push_outbound` / `sa_netx_broadcast` / `sa_netx_close_slot` / `sa_netx_shutdown`；契约写入新增的 `sa_std/netx.sai` 与 `sa_std/netx.sal`，**不修改 `sa_std/net.sai`**
11. WHEN TLS / HTTPS 必要 THEN 引擎 SHALL **不本地终结 TLS**，明确要求由前置反向代理（Nginx / Envoy / HAProxy）终结，SA 引擎只在安全内网裸跑 HTTP/TCP/WS；本期不实现 HTTP/2、HTTP/3 (QUIC)
12. WHEN 性能基线 THEN 引擎 SHALL 提供两条独立 KPI：
    - **K1（对标 Bun 单点 ping-pong）**：32 client × 64B 双向消息 ≥ 2,500,000 msg/s（持平 Bun v1.2），M6 阶段冲击 ≥ 3,500,000 msg/s（≥ 1.4× Bun）
    - **K2（SA 护城河广播）**：1 source × 10⁵ receivers × 1 KB payload ≥ 30 GB/s 总吞吐（≥ 10× Bun 同场景），CPU 占用 ≤ Bun 的 30%
13. WHEN 网络引擎落入文档 THEN 引擎 SHALL 在 `docs/network_engine_plan.md` 维护完整施工蓝图（v0.9+），并在 `docs/std_rfc.md` 登记 `sa_netx_*` 加入标准库的 RFC

**设计文档**：见 `docs/network_engine_plan.md`（§0–§8）

**决策来源**：talk.md 网络层四轮脑暴 + Bun/Deno/Node ws benchmark 对标

---

**决策来源**：talk.md 网络层四轮脑暴 + Bun/Deno/Node ws benchmark 对标

---

### Requirement 36: SAX 前端 UI 方言（v0.9 — Symbolic Affine XML，全栈 SA 闭环）

**User Story**  
作为 SA 生态的前端层，我需要一个不是"又一个 JS 框架"的 UI 方言：在 `.sa` 之上仅增加 XML 结构层，编译目标直接是 WebAssembly + HTML，由同一套 Flattener / Referee 验证，把后端 EXE 与前端 WASM 统一在一种语言、一套所有权契约下。

**Acceptance Criteria**

1. WHEN `.sax` 源文件被处理 THEN 编译器 SHALL 在 `src/sax/` 提供独立前端层（已存在 `parser.zig` / `lowerer.zig` / `airlock_gen.zig` / `sax_rules.zig` / `cli.zig` / `mod.zig`），输出**合法 `.sa` 文本**，**不构造任何 AST、不引入新的 SA-ASM 指令、不修改 ISA**
2. WHEN SAX Parser 解析 `<Component name="X">` THEN 解析器 SHALL 识别 `<state>` 块、DOM 树（XML 标签 + `{expr}` 插值）、`@handler:` 函数体、`!var1 !var2` 释放序列；DOM 树降级为 `@ffi_wrapper` 内对 Airlock `@extern` 的调用，状态变量降级为 `alloc N` + 固定偏移 `store`
3. WHEN `<state>` 变量被声明 THEN 每条声明 SHALL 一行一变量；类型由字面量或 `as T` 推断（同 `.sa`）；**每个 `<state>` 变量必须出现在组件结尾的 `!var` 释放序列中**，遗漏触发 `Trap: SaxStateLeak`
4. WHEN `{expr}` 出现在文本或属性值 THEN 表达式 SHALL 是只读 SA 表达式（`load` / 算术），**禁止包含 `^`（Move）或 `!`（Release）**，违规触发 `Trap: SaxInvalidInterpolation`
5. WHEN `onclick={^handler}` 等事件属性出现 THEN `^handler` SHALL 产生 `BorrowView` 掩码并指向**同一 `<Component>` 内**定义的 `@handler:`；跨组件引用触发 `Trap: SaxEventEscape`；支持事件白名单（`onclick onchange oninput onsubmit onkeydown onkeyup onfocus onblur onmouseenter onmouseleave`），未在白名单内触发 `Trap: SaxUnknownEvent`
6. WHEN DOM 标签被使用 THEN 标签 SHALL 在 HTML5 白名单内（`div / section / article / header / footer / main / nav / aside / h1-h6 / p / span / label / strong / em / button / input / textarea / select / option / form / ul / ol / li / table / thead / tbody / tr / th / td / img / video / canvas` + SAX 保留 `<Router> / <Page> / <Slot>`），其他标签触发 `Trap: SaxUnknownTag`
7. WHEN `call @render()` 出现 THEN 此调用 SHALL 仅出现在 `@handler:` 函数体内；初始化由 Lowerer 自动插入首次渲染；其他位置出现触发 `Trap: SaxRenderOutsideHandler`
8. WHEN 组件外部代码尝试写入某 Component 的 `<state>` 内存槽 THEN Referee SHALL 触发 `Trap: SaxStateWriteFromOutside`，保证组件状态封装性
9. WHEN Referee 验证 SAX 派生的 `.sa` THEN 验证器 SHALL 复用 SA 现有 23 条 Trap，并在 `src/sax/sax_rules.zig`（约 200 行）追加 7 条 SAX 专属 Trap：`SaxStateLeak / SaxEventEscape / SaxRenderOutsideHandler / SaxInvalidInterpolation / SaxStateWriteFromOutside / SaxUnknownTag / SaxUnknownEvent`，每条附带 `component / handler / tag / event / upstream_loc` 诊断字段
10. WHEN DOM Airlock 被声明 THEN Airlock SHALL 严格遵守 SA 气闸舱 FFI（R13）：所有 DOM 操作通过 `@extern` 声明，**只能在 `@ffi_wrapper` 内调用**；`airlock.js` 由 `airlock_gen.zig` 自动生成，是 WASM ↔ DOM 的唯一合法通道；不接受字符串形式的事件 / 选择器注入；`sax_dom_set_text` 必须使用 `textContent`（禁用 `innerHTML`）；`sax_dom_set_attr` 仅允许属性白名单（`class / style / value / placeholder / disabled`），`href / src` 等敏感属性需独立 API
11. WHEN CLI 提供 SAX 子命令 THEN CLI SHALL 支持至少 4 条：`sa sax build <file.sax>`（→ `app.wasm + airlock.js + index.html`）、`sa sax check <file.sax>`（仅 Referee 验证）、`sa sax new <name>`（脚手架）、`sa sax dev`（Phase 2，热重载）
12. WHEN WASM 产物落地 THEN 编译目标 SHALL 是 `wasm32-unknown-unknown`（**非 WASI**，纯浏览器环境）；复用现有 `src/emit_wasm/` 后端，**零修改**；`flattener/` / `common/` 完全复用，零修改；`referee/` 仅追加 `sax_rules.zig`
13. WHEN 项目以 SAX 为唯一前端入口 THEN SAX SHALL **不提供** `v-if / v-for / v-model / JSX 表达式嵌套 / 隐式响应式追踪 / async-await 直接语法 / CSS-in-JS / SSR / 隐式 Drop`；控制流统一走扁平 `L_LABEL:` + `br` / `jmp`；状态泄漏一律编译期触发 `SaxStateLeak`
14. WHEN SAX 文档落地 THEN 引擎 SHALL 在 `docs/sax_whitepaper.md`（v0.1+）、`docs/sax_design.md`、`docs/sax_airlock.md`、`docs/sax_syntax.md` 维护完整契约；`docs/std_rfc.md` 登记 SAX 加入标准库的 RFC

**设计文档**：见 `docs/sax_whitepaper.md` / `docs/sax_design.md` / `docs/sax_airlock.md` / `docs/sax_syntax.md`

**决策来源**：web.md 前端方言讨论 + 现有 `src/sax/` 五件套实现（parser / lowerer / airlock_gen / sax_rules / cli）

---

### Requirement 37: 宏驱动高级特性演进 (Macro-Driven Advanced Features)

**User Story**  
作为高级语言（如 Rust）的降级目标，我需要 SA-ASM 在保持指令集（ISA）极简（Zero-ISA 扩展）的同时，具备等同于 Rust 的高级安全特性与抽象能力。

**Acceptance Criteria**
1. WHEN 需要实现动态分发（`dyn Trait`）THEN 编译器与宏系统 SHALL 采用**去功能化 (Defunctionalization)** 路线：通过宏 `[MACRO] DISPATCH` 生成基于 Enum Tag 的静态分支路由树（`eq` + `br`），以 O(log N) 的极低损耗模拟间接调用，**禁止向 ISA 添加 `call_indirect` 函数指针指令**。
2. WHEN 需要处理安全枚举与模式匹配（Sum Types / Tagged Unions）THEN 编译器 SHALL 提供标准宏 `[MACRO] MATCH_RESULT`：自动根据内存 Layout 中的 Tag 执行安全解包和穷尽性匹配（Exhaustive Match），屏蔽底层的裸指针偏移计算，防止内存越界。
3. WHEN 处理大型结构体（如网络引擎中的 `ConnectionSlot`）THEN `referee.zig` SHALL 支持**细粒度字段级借用 (Disjoint Field Borrows)**：识别 `ptr_add obj, offset` 产生的借用是相互独立的，允许对同一结构体的不同字段同时进行不冲突的借用，无需引入新语法。
4. WHEN 处理资源释放（RAII）THEN 编译器 SHALL 通过**作用域收尾宏 (如 `[MACRO] DROP_AND_RETURN`)**：将资源释放指令 `!` 与 `return` 强制捆绑，确保在任何提前返回路径下资源均被正确释放，防止内存或文件描述符泄漏，且无需引入运行时的 `defer`。
5. WHEN 进行多线程通信（如 `sa_net_uring` 中的 SpscRing）THEN `verifier.zig` SHALL 增加 **Send / Sync 类似机制的静态边界约束**：对 Capability 的多线程逃逸进行校验，保障跨核数据投递不发生 Data Race。

---

### Requirement 38: 工业级性能与线性伸缩性 (Industrial-Scale Performance & Linear Scalability) - 紧急 P0

**User Story**  
作为大型工程的构建系统，我需要编译器在面对万级函数（10k+ Functions）时，内存占用与编译耗时能保持线性增长（$O(N)$），而不是由于寄存器全局化导致的平方级增长（$O(N^2)$）。

**Acceptance Criteria**
1. WHEN 编译包含 10,000 个以上函数的源文件 THEN 内存占用 SHALL 与函数总量成线性关系 ($O(N)$)，禁止出现由于全量寄存器快照导致的内存爆炸。
2. WHEN 执行所有权验证 THEN `Verifier` SHALL 确保寄存器作用域局部化：每个函数的校验快照仅包含该函数活跃的寄存器，**禁止跨函数携带不相关的寄存器状态**。
3. WHEN 存储验证元数据 THEN `AnnotatedInstruction` SHALL 采用稀疏存储结构（Sparse Tracking）：仅记录发生变更的寄存器掩码位，避免在长路径下存储海量冗余 `u16` 数组。
4. WHEN 发射中间代码 THEN `Emitter` SHALL 采用流式（Streaming）写入机制：边校验边发射到 Buffer/Disk，确保中间内存占用不随代码行数呈线性累积以外的增长。
5. WHEN 执行百万行级验证 THEN 编译器在 4 核标准开发机上的全流程编译速度（Flattener + Verifier + Streaming Emitter）SHALL 保持在 **500K 行/秒** 以上。

---

### Requirement 39: 极简格式化打印与字符串插值 (Minimal Formatted Printing & Interpolation)

**User Story**  
作为开发者，我需要类似 Rust `println!` 的高层级打印能力，以便快速调试和输出结构化数据，而不是手动拼接多个 `STRFMT_*` 宏和调用 `@sys_print`。

**Acceptance Criteria**
1. WHEN 标准库被引入 THEN 其 SHALL 提供标准宏 `[MACRO] PRINT! %fmt, %args...` 和 `[MACRO] FORMAT! %fmt, %args...`。
2. WHEN 宏展开发生 THEN 其 SHALL 采用**静态展开**策略：根据 `%fmt` 字符串（需为字面量）中的占位符 `{}`，自动生成对应的 `STRFMT_I64` / `STRFMT_F64` / `STRFMT_BYTES` 序列，并将产物拼接后一次性输出。
3. WHEN 处理复杂类型（如结构体）THEN 打印系统 SHALL 配合 R32 的布局标签，支持可选的 `{:?}` 语法，通过编译器生成的反射字典自动展开成员打印。
4. WHEN 内存受限场景下 THEN 打印宏 SHALL 允许指定输出 Buffer，避免频繁的 `alloc/free`。
5. WHEN 验证时 THEN 打印宏的展开结果 SHALL 符合 SA 的线性所有权契约，所有临时生成的字符串缓冲区必须在打印结束后被立即 `!` 释放，严禁内存泄漏。

---

**文档终态：以上 39 条 Requirements（R1–R24 MVP + R25–R27 v0.3 + R28–R30 v0.4 + R31–R32 v0.5 + R33 v0.6 + R34 v0.6 sa-db + R35 v0.8 sa_netx + R36 v0.9 SAX + R37 Macro-Driven + R38 Industrial-Scale + R39 Formatted-Printing）为 SA 实现的强约束契约。任何后续 Design 阶段不得弱化或绕过已有特性。**

> 版本号说明：v0.7 已规划为"原生单元测试框架"（见 `tasks.md` Version 0.7），v0.8 网络引擎，v0.9 SAX 前端方言。
