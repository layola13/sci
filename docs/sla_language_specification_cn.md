# Sla: 安全线性语言设计规范与评估报告

> **设计日期**：2026年6月14日
> **版本**：v0.1-草案
> **目标平台**：SA (Safe ASM) v0.1
> **目标**：定义一门简单的、静态类型、支持 AST 的高级脚本语言，可编译为 fully tracked 且符合 Referee 静态验证的 SA 汇编，从根本上解决 SA 原生的所有权及分支状态管理难题。

---

## 1. 核心定位与设计哲学

**Sla**（读作 /slɑː/）是一门为 **SA (Safe ASM)** 量身定制的静态类型、面向表达式的线性/仿射系统编程语言。它旨在降低手写 SA 汇编的极高心智负担，提供以下核心价值：
1.  **AST 驱动的编译器前端**：支持解析成抽象语法树（AST），解决手写 SA 汇编时解析器函数的组合爆炸问题。
2.  **静态跟踪的仿射类型系统**：继承 SA 的 Move/Borrow 语义，但在编译期自动注入寄存器释放（`!reg`）和分支汇合状态平衡逻辑。
3.  **高级语法抽象**：原生支持 `if/else`、模式匹配 `switch/match` 以及单态化的泛型（Generics）。

---

## 2. 语法设计与 AST 映射

Sla 语法采用类似 Rust 的面向表达式风格。

### A. 基础类型映射
Sla 基础类型与 SA 的类型实现 1:1 的直接映射：
*   `int` $\rightarrow$ `i64` / `u64`
*   `float` $\rightarrow$ `f64`
*   `bool` $\rightarrow$ `u8` (0 为 false，1 为 true)
*   `T` (如结构体类型) $\rightarrow$ `ptr` (在 SA 层面受 Referee 跟踪的所有权堆或栈内存指针，对应其 Layout)
*   `&T` (借用类型) $\rightarrow$ `ptr` (在 SA 层面受 Referee 跟踪的借用指针)

### B. AST 结构节点
编译器将 Sla 源码解析为结构化的 AST 树：
```
AST 节点类型:
├── Program(decls: List[Decl])
├── Decl
│   ├── StructDecl(name: String, generics: List[String], fields: List[Field])
│   └── FuncDecl(name: String, generics: List[String], params: List[Param], ret_ty: Type, body: Block)
├── Stmt
│   ├── Let(name: String, value: Expr)
│   ├── Assign(target: Expr, value: Expr)
│   └── ExprStmt(expr: Expr)
└── Expr
    ├── Literal(val: Any)
    ├── Var(name: String)
    ├── If(cond: Expr, then_branch: Block, else_branch: Block)
    ├── Switch(val: Expr, cases: List[Case])
    ├── Binary(op: Op, left: Expr, right: Expr)
    ├── Call(func: String, generics: List[Type], args: List[Expr])
    └── Borrow(expr: Expr)
```

---

## 3. 高级特性的 SA 降级（Lowering）实现

### 1. `if/else` 的自动 Phi 汇合与生命周期修复

在底层的 SA 汇编中，Divergent Branches（分叉分支）在跳转到同一个 Merge 点时，每个寄存器的状态必须完全一致，否则触发 `PhiStateConflict` 错误。

**在 Sla 中**：编译器在 AST 层面进行活跃变量分析。当编译 `if/else` 语句时，Sla 编译器会**自动对比**两个分支结束时的活跃寄存器差异，并在 merge 汇合点前**自动注入**必要的 `!reg`（释放/消费）操作。

#### Sla 源码
```sla
let x = alloc_struct();
if cond {
    use_and_consume(x); // x 在此处被移动/消费 (Move)
} else {
    // x 在此分支未被消费
}
// 分支汇合点
```

#### 编译后生成的 SA 汇编 (自动生成)
```sa
    // x 处于 Active 状态
    br cond -> L_THEN, L_ELSE
    
L_THEN:
    call @use_and_consume(x) // x 状态变为 Consumed
    jmp L_MERGE
    
L_ELSE:
    // x 仍处于 Active 状态。为了消除 L_MERGE 点的 Phi 状态冲突，
    // Sla 编译器会自动在出口注入释放指令：
    !x // x 状态强制转为 Consumed
    jmp L_MERGE
    
L_MERGE:
    // SA 校验通过：无论走哪个分支，x 在汇合点都安全地处于 Consumed 状态
```

---

### 2. 模式匹配 `switch` 表达式

SA 并不支持 switch 分支。Sla 将其抽象为高级的模式匹配，并在编译后端降低为 flat branch ladder（`eq` + `br` 链），同时自动回收未命中的匹配目标。

#### Sla 源码
```sla
switch val {
    1 => return 100,
    2 => return 200,
    default => return 0
}
```

#### 编译后生成的 SA 汇编
```sa
    is_1 = eq val, 1
    br is_1 -> L_CASE_1, L_CHECK_2
    
L_CHECK_2:
    !is_1
    is_2 = eq val, 2
    br is_2 -> L_CASE_2, L_DEFAULT
    
L_CASE_1:
    !is_1
    !val // Sla 自动注入：未使用的匹配目标在此分支销毁
    return 100
    
L_CASE_2:
    !is_2
    !val // Sla 自动注入：未使用的匹配目标在此分支销毁
    return 200
    
L_DEFAULT:
    !is_2
    !val // Sla 自动注入：匹配目标在默认分支销毁
    return 0
```

---

### 3. 单态化泛型支持（Monomorphization）

SA 本身没有泛型和多态概念。Sla 编译器采用与 Rust / C++ 模板类似的**编译期单态化（Monomorphization）**机制。

当编译器解析到泛型结构体 `Box<T>` 或函数 `identity<T>(x: T)` 时：
1.  编译器并不直接为泛型生成代码。
2.  在调用处或实例化处，编译器记录具体的类型实参（例如 `Box<int>`，`Box<Item>`）。
3.  编译器为每种类型实例化组合生成专用的 `.sal` 布局和 `.sa` 强类型函数。

#### Sla 泛型源码
```sla
struct Box<T> {
    val: T
}

fn identity<T>(x: T) -> T {
    return x
}
```

#### 编译后生成的 SA 结构（实例化为 `Box[int]` 后的输出）
```sal
// layout_box_int.sal - 自动生成的结构体布局
#struct Box_int_Layout {
    val: i64
}
```
```sa
// code_box_int.sa - 自动生成的单态化函数
@identity_int(x: i64) -> i64:
L_ENTRY:
    return x
```

---

### 4. 方法链接（链式调用）与 UFCS 支持

在仿射/线性类型系统中，数据结构的更新（如向 `Vec` 追加元素）通常会消费（Move）旧的实例并返回新的实例。为了避免深层嵌套的函数调用结构（例如 `push(push(v, 1), 2)`），Sla 提供了方法语法（Method Syntax）以及链式调用（Method Chaining）支持。

#### 设计原理
Sla 并不在运行时引入面向对象的动态派发（Dynamic Dispatch），而是通过**通用函数调用语法（UFCS）**在编译期进行静态展开：
*   **语法转换**：对于任意表达式 `x.method(y)`，编译器首先通过 `x` 的静态类型（如 `Vec<T>`）推导其关联的函数，并将其翻译为静态函数调用：`method(x, y)`。
*   **链式调用**：当方法返回接收者类型本身或其它新对象时，可以直接进行链式调用：`v.push(1).push(2)` 在 AST 降级时会被直接展平为 `push(push(v, 1), 2)`。

#### 自动借用与自动移动（Auto-Borrow / Auto-Move）
为了提升开发体验，Sla 编译器在处理方法接收者（Receiver）时会自动分析函数签名：
1.  **自动借用**：若被调用的函数签名第一个参数为借用类型 `&T`，但调用传入的是值类型 `v`，编译器会自动将其改写为 `&v`。例如，`v.len()` 自动转换为 `len(&v)`。
2.  **自动移动**：若签名第一个参数为值类型 `T`（需转移所有权），编译器会自动将其改写为 `^v`。例如，`v.push(1)` 自动转换为 `push(^v, 1)`。

#### Sla 源码
```sla
let v = vec_new();
let final_v = v.push(10).push(20);
```

#### 降级转换后的普通函数形式
```sla
let v = vec_new();
let final_v = push(^(push(^v, 10)), 20);
```

---

### 5. 错误传播与后缀 `?` 运算符

为了在不增加任何新关键字（保持严格 12 个关键字）的前提下提供优雅的错误传播机制，Sla 引入了后缀 `?` 运算符。

#### 设计原理
*   **语法表现**：`?` 是一个后缀一元运算符，仅能作用于返回 `Result<T, E>` 类型（或任何包含 `is_err: bool`、`value: T`、`error: E` 类似结构的联合/结构体类型）的表达式。
*   **AST 展开**：`let x = expr?;` 在 AST 降级时，会被编译器自动展开为条件分支检查：
    1.  若结果是 `Err`，则提取其错误字段，并在自动执行当前作用域内所有活跃变量的生命周期清理（注入 `!`）后，提前返回 `Err(error_val)`。
    2.  若结果是 `Ok`，则通过移动语义（`^`）解包出内部的 `value` 字段，并继续执行后续代码。

#### Sla 源码
```sla
fn process_data() -> Result<int, Error> {
    let data = fetch_from_db()?;
    return Ok(data + 1);
}
```

#### 降级转换后的 Sla 表达形式
```sla
fn process_data() -> Result<int, Error> {
    let temp_res = fetch_from_db();
    if temp_res.is_err {
        let err = ^temp_res.error;
        !temp_res;
        
        // 自动生成的生存期代偿（清理当前作用域所有活跃局部变量）
        
        return Err(^err);
    }
    let data = ^temp_res.value;
    !temp_res;
    
    return Ok(data + 1);
}
```

---

## 4. 完整的 Sla $\rightarrow$ Tracked SA 映射实例

### Sla 源码 (`example.sla`)
```sla
struct Option<T> {
    has_value: bool,
    value: T
}

fn process_option(opt: Option<int>) -> int {
    if opt.has_value {
        let val = opt.value;
        !opt; // 释放外层 Option 包装，回收其占用的内存
        return val;
    } else {
        !opt; // 释放外层 Option 包装
        return -1;
    }
}

// 新增：数值区间循环示例，展示循环结构在 Sla 中的 Lowering 表现
fn sum_range(limit: int) -> int {
    let sum = 0;
    for i in 1..limit {
        sum = sum + i;
    }
    return sum;
}
```

### 生成的静态布局 (`example.sal`)
```sal
// 静态映射 Option<int> 结构的内存布局
#struct Option_int_Layout {
    has_value: u8,   // 偏移量 +0
    value: i64       // 偏移量 +8 (对齐)
}
```

### 生成的 Tracked SA 汇编 (`example.sa`)
```sa
@import "example.sal"

@process_option(opt: ptr) -> i64:
L_ENTRY:
    // 直接根据 example.sal 中定义的结构体偏移量加载数据
    has_val = load opt+0 as u8
    is_true = eq has_val, 1
    br is_true -> L_THEN, L_ELSE
    
L_THEN:
    !is_true
    !has_val
    // 移动/提取内部字段 value 的所有权
    val = load opt+8 as i64
    !opt // 释放 opt 占用的 Option_int_Layout 堆空间
    return val
    
L_ELSE:
    !is_true
    !has_val
    !opt // 同样释放 opt 占用的堆空间，保证分支汇合状态对称
    return -1

// 新增：编译 sum_range 后生成的循环结构 SA 汇编
@sum_range(limit: i64) -> i64:
L_ENTRY:
    sum = 0
    // 为循环计数器分配局部栈空间
    i_slot = stack_alloc 8
    store i_slot+0, 1 as i64
    jmp L_LOOP_HEAD

L_LOOP_HEAD:
    i = load i_slot+0 as i64
    is_less = slt i, limit
    br is_less -> L_LOOP_BODY, L_LOOP_EXIT

L_LOOP_BODY:
    !is_less
    sum = add sum, i
    next_i = add i, 1
    store i_slot+0, next_i as i64
    !next_i
    !i
    jmp L_LOOP_HEAD

L_LOOP_EXIT:
    !is_less
    !i
    !i_slot
    !limit // 释放已不再使用的 limit 参数，确保所有权平衡
    return sum
```

---

## 6. 所有权符号 `&`, `^`, `!` 的保留与设计评估

为了让开发者在高级语言 Sla 中获得纯正的 **SA 所有权验证体验**，Sla 对 SA 的核心所有权符号进行了显式的保留和语法设计。这在编译期构建起了一套“显式契约，隐式代偿”的混合系统。

### A. 移动（Move）符号：`^`
*   **设计抉择**：**完全保留**。
*   **语法表现**：`let y = ^x;` 或 `call_func(^x);`。
*   **编译映射**：1:1 降低为 SA 的 `^`。
*   **体验价值**：当开发者在 Sla 中使用 `^x` 时，能直观地感受到**所有权转移（Move Semantics）**的发生。被移动后的变量 `x` 将在 Sla 编译器的符号表中被标记为 `Consumed`。后续如果在代码中再次引用 `x`，Sla 编译器将在前端抛出明确的 `UseAfterMove` 错误，实现与 SA Referee 相同的编译期拦截。

### B. 借用（Borrow）符号：`&`
*   **设计抉择**：**完全保留**。
*   **语法表现**：`let ref_x = &x;`。
*   **编译映射**：1:1 降低为 SA 的 `&`。
*   **体验价值**：支持借用是避免频繁 Move 的核心。在 Sla 中使用 `&x` 将创建对 `x` 的借用视图。此时，Sla 的借用检查器（Borrow Checker）会根据代码的控制流静态计算它是 `Locked_Read` 还是 `Locked_Mut` 借用，并在作用域结束时自动注入 `!ref_x` 解锁，开发者无需手动解锁，同时可以体验到 SA 优异的并发别名冲突检查。

### C. 释放（Release / Free）符号：`!`
*   **设计抉择**：**保留显式 `!` 运算，同时由编译器在作用域结束时提供隐式代偿**。
*   **语法表现**：`!x;`。
*   **编译映射**：1:1 降低为 SA 的 `!x`。
*   **双轨设计**：
    1.  **显式 `!x`**：允许开发者在函数体中间手动提前释放变量（例如在大循环前手动清理内存）。一旦显式 `!x` 执行，`x` 在符号表中就被标为 `Consumed`。
    2.  **隐式代偿**：如果变量 `x` 在作用域（Block）结束时仍处于 `Active` 状态，Sla 编译器会**自动在 Block 结束前注入 `!x`**。这既保证了满足 SA Referee 规避 `MemoryLeak` 的强制规则，又把开发者从“在每个 return 前手动打几十个 `!var`”的冗余垃圾代码中解放了出来。

---

## 7. Sla 编译器开发路线图

Sla 编译器可以通过 Rust 或 Zig 进行独立的前端实现，其降低管线如下：

```
[第 1 个月：前端构建]
  ├── 实现 Sla 词法分析器 (Lexer) 与 AST 解析器 (Parser)
  └── 建立作用域 (Scope) 与静态符号表 (Symbol Table)

[第 2 个月：类型推导与泛型实例化]
  ├── 实现静态类型检查器
  ├── 开发泛型单态化（Monomorphizer）引擎
  └── 输出具体实例化后的布局文件 (.sal)

[第 3 个月：生存期跟踪与代码生成]
  ├── 构建控制流分析图，跟踪变量活跃度与生存期
  ├── 实现分支合并点前自动注入 `!reg` 的逻辑，规避 Phi 冲突
  └── 输出最终的 Tracked .sa 汇编代码

[第 4 个月：集成与测试]
  └── 接入 sci 项目的 Referee 静态验证器和二进制生成管线，进行全链路测试
```

---

## 8. 综合设计实例：包含全部核心特性的 Sla 源码

以下是一个完整的 Sla 源码实例，展示了结构体、泛型、卫生宏、`if/else`、模式匹配 `switch`、显式 `^` 移动、显式 `&` 借用、显式 `!` 释放以及编译期生命周期推导的结合。

```sla
// 1. 定义一个泛型结构体 (Option)
struct Option<T> {
    has_value: bool,
    value: T
}

// 2. 定义一个卫生宏 (Hygienic Macro)
macro swap(a, b) {
    let temp = ^a;
    a = ^b;
    b = ^temp;
}

// 3. 定义一个包含所有权转移的泛型函数
// opt 通过所有权传递，会被此函数消费
fn unwrap_or<T>(opt: Option<T>, default_val: T) -> T {
    // 使用 if/else 语句
    if opt.has_value {
        // 使用 '^' 将内部值移动出来
        let val = ^opt.value;
        
        // 显式消费 opt 容器本身
        !opt; 
        
        // 显式释放未使用的 default_val (避免 MemoryLeak)
        !default_val; 
        
        return val;
    } else {
        let val = ^default_val;
        
        // 显式释放空 Option 容器
        !opt; 
        
        return val;
    }
}

// 4. 定义一个使用卫生宏、循环（含循环内栈分配）、借用与模式匹配的函数
fn process_and_inspect(status: int, config_val: &int) -> int {
    // 借用操作 &
    let current_config = *config_val; // 读取借用指针的内容
    let offset = 100;
    
    // 数值循环与栈分配自动提升示例 (循环内的 temp 栈变量会被编译器自动提升至循环外)
    let sum = 0;
    for i in 1..5 {
        let temp = stack_alloc(8); // 8 字节栈分配，自动提升至循环外以防 Phi 冲突
        store temp+0, i as int;
        sum = sum + (load temp+0 as int);
        !temp; // 释放局部变量
    }
    
    // 调用卫生宏进行值交换 (展开时自动进行命名混淆以防冲突)
    swap(current_config, offset);
    !offset; // 释放不再使用的临时变量
    
    // 模式匹配 switch 语句
    switch status {
        200 => {
            // 返回计算结果，config_val 在 Block 结束时由编译器隐式 ! 释放借用
            return current_config + sum;
        },
        500 => {
            !sum; // 释放不再使用的临时变量
            return -1;
        },
        default => {
            !sum; // 释放不再使用的临时变量
            return 0;
        }
    }
}
```

### 编译为 SA 时的映射关系：
*   `Option<int>` 的实例将生成对应的 `Option_int_Layout.sal` 文件，使用静态偏移量加载。
*   `unwrap_or<int>` 单态化生成名为 `@unwrap_or_int` 的安全函数。
*   `swap` 宏编译为 SA 的 `[MACRO]`，调用处降级为 `EXPAND` 并自动混淆局部变量 `temp` 以防名字捕获。
*   `for i in 1..5` 循环体中的 `stack_alloc` 语句被编译器在编译期自动提升（Hoist）至循环头部 Label 之前，在循环体内被安全复用以规避 SA 的 Phi 状态冲突。
*   `process_and_inspect` 里的 `switch` 被降低为 conditional jump 分支，并在每个分支结束前，由编译器自动生成所需的 `!current_config` 和对借用的注销。

---

## 9. 极简关键字策略 (Minimal Keyword Policy)

为了保持 Sla 的“尽可能简单”的设计初衷，Sla 拒绝引入任何非常规或平台特定的自定义关键字（例如去掉了 `Own`、`Ref` 等）。Sla 的关键字集合严格限制在以下 12 个最基础的 C/Rust 风格关键字上：
*   **结构与函数**：`struct`、`fn`
*   **控制流**：`if`、`else`、`switch`、`return`
*   **循环迭代**：`for`、`in`
*   **变量与常量**：`let`、`const`
*   **编译修饰**：`inline`
*   **宏定义**：`macro`

所有权状态转移完全通过类型语法本身与 `=`（绑定）、`&`（借用）、`^`（移动）、`!`（释放）这四个符号的组合来表达，语法纯净度达到极致。

---

## 10. 关于宏（Macros）的映射与去留评估

在 SA 中，预处理器宏（`[MACRO]`、`EXPAND`、`#def`）被极度重度地使用。但在高级语言 Sla 中，我们的设计抉择是：**弃用不安全的文本级宏（`[MACRO]`），在编译器前端实现安全的卫生宏（Hygienic Macros），并将其在后端 1:1 降低为 SA 的 `[MACRO]`。**

### 为什么 Sla 不需要 SA 风格的原始文本宏？

SA 依赖原始文本宏，主要是为了解决缺少泛型、缺少自动生命周期清理等问题。Sla 在语言层面已经通过泛型单态化和生存期分析器解决了这些问题。

但在许多涉及底层包装和高度复用代码的场景中，宏系统依旧不可或缺。为了确保安全性，Sla 引入了安全的 **卫生宏（Hygienic Macros）**，彻底避免变量污染与名字捕获冲突。

---

## 11. Sla 卫生宏设计与 SA [MACRO] 映射

为了在 Sla 中提供与 Rust 类似的**安全卫生宏（Hygienic Macros）**，同时在底层无缝映射到 SA 的文本级 `[MACRO]` 预处理器，Sla 编译器采用了一种**编译期混淆与参数重命名（Alpha-conversion）**的设计。

### 核心挑战
*   **SA 的 `[MACRO]` 是非卫生的（Unhygienic）**：它只是简单的文本替换，如果在宏里声明了一个临时变量 `temp`，很容易与外部作用域里的 `temp` 发生名字冲突或遮蔽。
*   **Sla 必须保证卫生性**：宏内部定义的局部标识符不能泄露到外部，反之亦然。

### Sla 卫生宏的设计方案

1.  **语法表现（`macro` 关键字）**：
    Sla 引入了 `macro` 关键字来定义卫生宏：
    ```sla
    macro swap(a, b) {
        let temp = ^a;
        a = ^b;
        b = ^temp;
    }
    ```
2.  **编译期重命名（Alpha-Conversion）**：
    Sla 编译器在解析宏定义并构建 AST 时，会自动将宏体内部定义的所有局部变量（例如 `temp`）重命名为全局唯一的混淆名称（例如 `swap_temp_unique_99`）。
3.  **1:1 降低为 SA 的 `[MACRO]`**：
    重命名后，Sla 编译器直接输出 SA 兼容的 `[MACRO]`，将宏参数映射为 `%a`, `%b`。

#### 生成的 SA 代码结构
```sa
    // Sla 编译器自动输出 of SA 宏定义（已在编译期保证了变量名 temp 的唯一性）
    [MACRO] swap_hygiene %a, %b
        // 局部变量已在 Sla 前端被重命名，完美规避了 SA 底层的命名冲突
        swap_temp_unique_99 = ^%a
        %a = ^%b
        %b = ^swap_temp_unique_99
        !swap_temp_unique_99
    [END_MACRO]
```
当在 Sla 中调用 `swap(x, y)` 时，编译器直接生成 SA 的宏展开：
```sa
    EXPAND swap_hygiene x, y
```

这套机制完美达成了两个目标：**开发者在 Sla 中体验到的是高级、防污染的 Rust 级卫生宏；而编译器在底层生成的是 1:1 的 SA 原生 `[MACRO]` 结构。**

---

## 12. 数值 `for` 循环与栈分配自动提升 (Numeric `for` Loops)

Sla 支持简单直观的 Rust 风格数值区间循环：`for i in start..end { ... }`。

### 核心物理限制：循环体内的 `stack_alloc` 冲突
在底层 SA 汇编中，直接在循环体内使用 `stack_alloc`（栈分配）会面临严重的 Referee 约束。如果在循环内部多次分配，因为循环会多次跳转回 Label 头，会导致 verifier 无法判定局部变量的初始状态，从而报 `PhiStateConflict` 或 `StackEscape` 错误。

### Sla 编译器的自动提升（Automatic Hoisting）方案

Sla 编译器在 AST 层面天然解决了这一难题。当解析到 `for` 循环时：
1.  **静态提升（Hoisting）**：编译器检测循环体内所有声明的 `stack_alloc` 局部变量。
2.  **前置分配**：自动将这些栈分配语句提升（Hoist）到循环头部 Label（如 `L_LOOP_HEAD`）之前进行单次分配。
3.  **循环复用**：在循环体内仅执行 `store`/`load` 覆盖写入，而不进行重复分配。
4.  **自动释放**：在循环体退出后，自动生成 `!` 指令释放栈空间。

#### Sla 源码
```sla
// 1..5 区间循环
for i in 1..5 {
    // 编译器会自动将该栈变量提升到循环外分配，避免 Phi 冲突
    let temp_buf = stack_alloc_bytes(); 
    do_something(&temp_buf, i);
}
```

#### 编译后生成的 SA 汇编 (自动提升)
```sa
    // 1. 自动提升：在循环前进行栈分配
    temp_buf = stack_alloc 16
    i_slot = stack_alloc 8
    store i_slot+0, 1 as i64
    
L_LOOP_HEAD:
    i = load i_slot+0 as i64
    is_less = slt i, 5
    br is_less -> L_LOOP_BODY, L_LOOP_EXIT
    
L_LOOP_BODY:
    !is_less
    // 执行业务逻辑，重用已分配的 temp_buf
    call @do_something(&temp_buf, i)
    
    // 计数器累加
    next_i = add i, 1
    store i_slot+0, next_i as i64
    !next_i
    !i
    jmp L_LOOP_HEAD
    
L_LOOP_EXIT:
    !is_less
    !i
    // 2. 自动释放：循环退出时自动消费销毁栈变量，规避内存泄露
    !i_slot
    !temp_buf
```
通过自动提升技术，开发者可以自由地在 `for` 循环内书写干净的局部逻辑，而无需手动管理低级汇编的栈帧时序。
```

---

## 13. 与 `sa_std` 的标准库映射机制 (Standard Library Mappings)

Sla 坚守“不重复造轮子”的原则。由于 `sa_std` 中已经拥有通过 SA 汇编或底层宏实现的高性能 `Box`、`Rc`、`RefCell`、`Vec`、`HashMap` 等数据结构，Sla 提供了简洁的 **`extern` 映射机制**，直接将 Sla 的高级泛型接口映射到已有的 `sa_std` 实现，实现零开销桥接。

### 1. 外部布局映射 (`extern struct`)
Sla 支持通过 `extern struct` 声明将高级泛型结构体与外部的 `.sal` 布局关联：
```sla
// Sla 标准库声明 (rc.sla)
@import "sa_std/rc.sal" // 导入 sa_std 原生导出的布局描述

// 声明外部结构体，告知编译器其具体物理布局由外部决定
extern struct Rc<T>;
```
在编译期，当 Sla 实例化 `Rc<int>` 时，编译器不会为其生成新的结构体布局，而是直接在生成的 SA 汇编中引用外部已定义好的 `Rc_int_Layout`，保证 ABI 级兼容。

### 2. 外部 API 映射 (`@extern fn`)
Sla 使用 `@extern` 修饰符声明外部的 SA 汇编函数或宏接口：
```sla
// 声明外部 sa_std 接口
@extern fn sa_std_rc_new<T>(val: T) -> Rc<T>;
@extern fn sa_std_rc_clone<T>(rc: &Rc<T>) -> Rc<T>;
@extern fn sa_std_rc_drop<T>(rc: Rc<T>);
```
Sla 中的高级调用会在 AST 降级时，直接翻译为对外部 SA 函数的 `call`：
```sla
// Sla 源码
let my_rc = sa_std_rc_new(val);

// 降级生成的 SA 汇编
my_rc = call @sa_std_rc_new(val)
```

### 3. 析构函数自动代偿映射 (Destructor Hooking)
对于非基础的外部资源类型（如 `Rc<T>`），当它们离开词法作用域时，Sla 编译器的隐式释放机制支持将其改写为对外部析构函数的调用，而非直接生成底层的 `!reg`（因为 `Rc` 的销毁涉及递减引用计数等复杂 SA 宏操作）：
```sla
// Sla 源码
{
    let my_rc = sa_std_rc_new(100);
    // 业务逻辑
} // 作用域结束

// 降级生成的 SA 汇编 (自动注入析构调用，而不是简单的 !my_rc)
call @sa_std_rc_drop(my_rc)
```

### 4. 直接复用 `.sal` 与 `.sai` 契约文件
为了实现真正的零副本（Zero-copy）和零人工声明开销，Sla 编译器前端内置了对 SA 原生 `.sal`（布局定义）与 `.sai`（接口声明）文件的解析器：
*   **`.sal` 直接解析**：Sla 编译器能够直接读取 `sa_std` 或第三方插件导出的 `.sal` 布局，并将其自动转换为 Sla 编译器前端类型系统中的结构体字段偏移，而不需要开发者重新在 Sla 中手写结构体定义。
*   **`.sai` 直接解析**：对于 `sa_std` 的 ABI（如 `@extern` 函数签名），Sla 能够通过 `@import "xxx.sai"` 直接读取其中定义的 FFI 函数类型签名，并自动在 Sla 前端注册为强类型函数。

这达成了两个重大目的：
1.  **极高的一致性**：Sla 在编译期看到的类型和 API 与 Referee 验证器在底层校验时看到的契约完全共享同一份 `.sal`/`.sai` 数据源，彻底杜绝了 ABI 漂移或双重声明不一致的风险。
2.  **插件生态开箱即用**：所有已有的 SA 插件（如 `sa_plugin_db`、`sa_plugin_http_client`）只要带有标准的 `.sai` 和 `.sal`，即可在 Sla 中通过一行 `@import` 直接进行强类型调用，无需任何胶水层。

通过该映射机制，Sla 编译器核心完全不需要硬编码任何智能指针或复杂数据结构的逻辑，只用极轻量级的声明，就能直接吞吐并调用 `sa_std` 的庞大底层生态。

---

## 14. Sla 编译器的战略定位与集成路线图 (Strategic Positioning & Roadmap)

Sla 作为一门面向 SA 静态生态的高级语言，其工程化落地秉持**“解耦迭代，安全先行”**的原则，采用分阶段的插件化演进战略。

### 1. 战略定位：插件化解耦开发 (Plugin-First Approach)
为了在逻辑上实现极速迭代，同时保障 SA 主仓（`sci`）编译器的绝对稳定性，Sla 编译器首先作为**独立的 SA 插件（`sa_plugin_sla`）**进行外置开发：
*   **物理屏障**：Sla 的编译器前端独立于 `sci` 主仓代码，Sla 语法分析器的崩溃或 Panic 不会影响主仓原生的 `sa compile` 和 `sa check` 工具链。
*   **物理生成**：Sla 插件作为转译器（Transpiler），读取 `.sla` 并输出合法的 `.sa` 汇编与 `.sal` 布局，随后直接将其交由核心的 `sa check` 去做 Referee 静态校验，保持极低耦合。
*   **验证插件系统**：作为原生插件开发能对 SA 自身的插件依赖与权限管理系统（`sap.json`）进行“吃狗粮（Dogfooding）”验证。

### 2. 演进路线图 (Evolutionary Roadmap)
Sla 编译器的生命周期划分为两个核心阶段：

#### 第一阶段：独立插件时代 (Sla Transpiler Plugin)
*   **开发实体**：位于单独的插件工程仓库 `/home/vscode/projects/sa_plugins/sa_plugin_sla`。
*   **编译流程**：用户通过 `sa plugin install sa_plugin_sla` 启用后，使用 `sa sla build app.sla -o app.sa` 将其翻译为低级 SA，再由主仓编译器进行汇编。
*   **目标**：跑通整个 Sla 前端类型推导、生命周期自动代偿、循环 hoisting 算法，并在此期间稳定 Sla 语言的语法设计。

#### 第二阶段：核心合并时代 (First-Class sci Language)
*   **集成实体**：Sla 前端实现整体合并至主仓 `sci` 代码树中。
*   **编译流程**：主仓 `sa` CLI 原生处理 `.sla` 扩展名，内部自动无缝走过 Sla ➔ SA ➔ Referee ➔ WASM/EXE 生成的完整管道。
*   **目标**：Sla 正式提升为整个安全编译生态的第一公民，彻底取代手写 SA 汇编，成为开发者进行业务和智能合约编写的首选高层语言。



