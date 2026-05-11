# Rust → SA 降级对照全集（v0.2 规范对齐版）

> 本文档严格按照 `.kiro/specs/sa-asm-language/` 下的 **requirements.md（R1–R24）** 与 **design.md** 规范，把 Rust 从最基础语法到最复杂的异步/多态逐一降级到 SA。
>
> 每个案例都会标注：
> - ✅ **顺畅**：SA 原生表达，降级代码清晰
> - ⚠️ **前端重担**：能表达但前端（smrustc/LLM）工作量大
> - ❌ **刻意缺失**：SA 规范不覆盖，把责任划给前端（设计取舍）
>
> 每个 SA 示例伪装为前端已完成词法作用域跟踪与隐式 Drop 插入后的产物（R20 合约）。
>
> **v0.1 与 v0.2 区别**：凡使用 `@const` / `stack_alloc` / `ptr_add` / `InteriorPtr` / `atomic_rmw_*` / `#mode compact` 的案例，均标为 v0.2 特性；v0.1 产物可降级为等价但更冗长的形态。

---

## 目录

### 基础特性
1. 变量与算术
2. 条件与循环
3. 所有权 Move
4. 共享借用 `&`
5. 独占借用 `&mut`
6. 结构体（字段偏移）
7. 数组索引与越界检查（`InteriorPtr`）
8. 字符串（胖指针 UTF-8）
9. Vec<T>（胖指针容器）
10. Box<T> / 栈分配（`stack_alloc`）

### 中级特性
11. Enum + match（标签联合）
12. Option<T> / Result<T, E>
13. `?` 错误传播
14. 函数参数的三种模式
15. 递归函数（链表遍历）
16. 生命周期标注 `'a`（刻意缺失）

### 高级特性
17. 泛型 + 单态化
18. Trait 静态分发
19. `dyn Trait` 动态分发（`@const` VTable）
20. 闭包（Lambda Lifting）
21. Iterator + for 循环
22. 原子操作（`atomic_rmw_*` + `cmpxchg` 双返回）
23. async/await（状态机展平）
24. Rc/Arc 引用计数（用 `atomic_rmw_sub`）
25. unsafe 块与裸指针（气闸舱）
26. FFI extern "C"
27. panic! / panic_msg

### v0.2 糖
28. `#mode compact` 紧凑中缀糖

---

## 1. 变量与算术 ✅

### Rust
```rust
fn sum(a: i32, b: i32) -> i32 {
    let c = a + b;
    let d = c * 2;
    d
}
```

### SA（v0.1 关键字形态）
```
#loc "basics.rs":1:1
@sum(a: i32, b: i32) -> i32:
L_ENTRY:
    c = add a, b
    d = mul c, 2
    return d
```

### SA（v0.2 `#mode compact` 形态，等价）
```
#mode compact
#loc "basics.rs":1:1
@sum(a: i32, b: i32) -> i32:
L_ENTRY:
    c = a + b
    d = c * 2
    return d
```

**说明**：两份源码经 Flattener 产出的 `Instruction[]` 字段级相等（P30 保证）。下文除非必要，默认用 v0.1 关键字形态。

---

## 2. 条件与循环 ✅

### Rust
```rust
fn abs_sum(arr: &[i32]) -> i32 {
    let mut sum = 0;
    let mut i = 0;
    while i < arr.len() {
        let v = arr[i];
        if v >= 0 {
            sum = sum + v;
        } else {
            sum = sum - v;
        }
        i = i + 1;
    }
    sum
}
```

### SA
```
#def Slice_data = +0
#def Slice_len  = +8
#def I32_SIZE   = 4

@abs_sum(arr: &Slice) -> i32:
L_ENTRY:
    sum = 0
    i = 0
    len = load arr+Slice_len as u64
    jmp L_COND

L_COND:
    cond = ult i, len
    br cond -> L_BODY, L_END

L_BODY:
    // 从借用的切片胖指针中派生内部数据指针（InteriorPtr，不需气闸舱，R13.6）
    data_base = load arr+Slice_data as ptr
    offset    = mul i, I32_SIZE
    data_ip   = ptr_add data_base, offset    // data_ip: InteriorPtr, 生命周期绑定 arr 借用
    v         = load data_ip+0 as i32

    neg = slt v, 0
    br neg -> L_NEG, L_POS

L_POS:
    sum = add sum, v
    jmp L_NEXT

L_NEG:
    sum = sub sum, v
    jmp L_NEXT

L_NEXT:
    i = add i, 1
    jmp L_COND

L_END:
    return sum
```

**说明**：
- 嵌套 `while { if/else }` 被展平为 5 个 Label 的 CFG
- `arr[i]` 用 `ptr_add + load` 降级，产物是 `InteriorPtr`（R4.9），**不触发气闸舱**（R13.6）
- `arr` 借用释放时，`data_ip` 自动进入 `Consumed`（R4.10）

---

## 3. 所有权 Move ✅

### Rust
```rust
struct Data { v: i32 }

fn consume(d: Data) {}

fn main() {
    let x = Data { v: 10 };
    consume(x);
    // println!("{}", x.v); // 编译错误
}
```

### SA
```
#def Data_SIZE = 4
#def Data_v    = +0

@consume(^d: ptr):
L_ENTRY:
    !d                      // 前端按 R20.1 显式释放
    return

@main:
L_ENTRY:
    x = alloc Data_SIZE
    store x+Data_v, 10 as i32
    call @consume(^x)
    // 此刻 x.mask == Consumed (0x08)
    // 任何对 x 的读写都会触发 UseAfterMove
    return
```

---

## 4. 共享借用 `&` ✅

### Rust
```rust
fn read_only(r: &i32) -> i32 { *r + 100 }

fn main() {
    let x = 42i32;
    let y = read_only(&x);
    let z = read_only(&x);
}
```

### SA
```
@read_only(r: &i32) -> i32:
L_ENTRY:
    v = load r+0 as i32
    res = add v, 100
    return res

@main:
L_ENTRY:
    x = stack_alloc 4             // v0.2 栈分配，无需 !x
    store x+0, 42 as i32

    r1 = &x
    y = call @read_only(&r1)
    !r1

    r2 = &x
    z = call @read_only(&r2)
    !r2

    return                         // stack_alloc 自动回收
```

**说明**：整数局部变量用 `stack_alloc`（R2.1、P27）避免堆分配开销。Referee 在函数出口对 `stack_alloc` 产物不查 `MemoryLeak`。

---

## 5. 独占借用 `&mut` ✅

### Rust
```rust
fn increment(r: &mut i32) { *r += 1; }

fn main() {
    let mut x = 10;
    increment(&mut x);
    let y = x;   // Rust NLL: r 已在函数返回时释放
}
```

### SA
```
@increment(r: &mut i32):
L_ENTRY:
    v  = load r+0 as i32
    v2 = add v, 1
    store r+0, v2 as i32
    return

@main:
L_ENTRY:
    x = stack_alloc 4
    store x+0, 10 as i32

    r = &mut x
    call @increment(&mut r)
    !r                              // 前端在 Rust NLL 终止点发射释放

    y = load x+0 as i32
    return
```

---

## 6. 结构体（字段偏移） ✅

### Rust
```rust
struct Vec3 { x: f32, y: f32, z: f32 }

fn length_sq(v: &Vec3) -> f32 {
    v.x * v.x + v.y * v.y + v.z * v.z
}
```

### SA
```
#def Vec3_SIZE = 12
#def Vec3_x    = +0
#def Vec3_y    = +4
#def Vec3_z    = +8

@length_sq(v: &Vec3) -> f32:
L_ENTRY:
    x  = load v+Vec3_x as f32
    y  = load v+Vec3_y as f32
    z  = load v+Vec3_z as f32
    xx = fmul x, x
    yy = fmul y, y
    zz = fmul z, z
    t  = fadd xx, yy
    res = fadd t, zz
    return res
```

---

## 7. 数组索引与越界检查（InteriorPtr） ✅

### Rust
```rust
fn get_or_zero(arr: &[i32], i: usize) -> i32 {
    if i < arr.len() { arr[i] } else { 0 }
}
```

### SA
```
#def Slice_data = +0
#def Slice_len  = +8
#def I32_SIZE   = 4

@get_or_zero(arr: &Slice, i: u64) -> i32:
L_ENTRY:
    len = load arr+Slice_len as u64
    ok = ult i, len
    br ok -> L_READ, L_ZERO

L_READ:
    data_base = load arr+Slice_data as ptr
    offset    = mul i, I32_SIZE
    data_ip   = ptr_add data_base, offset      // InteriorPtr
    v         = load data_ip+0 as i32
    return v

L_ZERO:
    return 0
```

**✅ 已修复**（v0.2 R13.6）：`ptr_add` 派生的 `InteriorPtr` 在普通函数内合法，无需进入 `@ffi_wrapper`。Referee 保证当 `arr` 借用被 `!` 释放时，`data_ip` 自动作废。

---

## 8. 字符串（胖指针 UTF-8） ⚠️

### Rust
```rust
fn count_a(s: &str) -> u64 {
    let mut count = 0u64;
    for b in s.bytes() {
        if b == b'a' { count += 1; }
    }
    count
}
```

### SA
```
#def Str_data = +0
#def Str_len  = +8
#def CHAR_a   = 97              // b'a'

@count_a(s: &Str) -> u64:
L_ENTRY:
    data = load s+Str_data as ptr
    len  = load s+Str_len  as u64
    count = 0
    i = 0
    jmp L_COND

L_COND:
    cond = ult i, len
    br cond -> L_BODY, L_END

L_BODY:
    cur  = ptr_add data, i        // InteriorPtr
    b    = load cur+0 as u8
    is_a = eq b, CHAR_a
    br is_a -> L_HIT, L_NEXT

L_HIT:
    count = add count, 1
    jmp L_NEXT

L_NEXT:
    i = add i, 1
    jmp L_COND

L_END:
    return count
```

**⚠️ 前端重担**：UTF-8 多字节字符迭代、`s.bytes()` Iterator 链的展平仍然要前端做。SA 本身只认字节数组。

---

## 9. Vec<T>（胖指针容器） ⚠️

### Rust
```rust
fn sum_vec(v: &Vec<i32>) -> i32 {
    let mut s = 0;
    for &x in v.iter() { s += x; }
    s
}
```

### SA
```
#def Vec_data  = +0
#def Vec_len   = +8
#def Vec_cap   = +16
#def I32_SIZE  = 4

@sum_vec(v: &Vec) -> i32:
L_ENTRY:
    data = load v+Vec_data as ptr
    len  = load v+Vec_len  as u64
    s = 0
    i = 0
    jmp L_COND

L_COND:
    cond = ult i, len
    br cond -> L_BODY, L_END

L_BODY:
    off  = mul i, I32_SIZE
    slot = ptr_add data, off
    x    = load slot+0 as i32
    s    = add s, x
    i    = add i, 1
    jmp L_COND

L_END:
    return s
```

**⚠️ 前端重担**：泛型 `Vec<T>` 必须被前端分别单态化为 `Vec_i32` / `Vec_String` 等，各自的 `element_size` 是编译期常量（通过 `#def` 注入）。

---

## 10. Box<T> / 栈分配（`stack_alloc`） ✅

### Rust
```rust
// 堆分配
fn boxed_double(x: i32) -> Box<i32> {
    Box::new(x * 2)
}

// 编译器会把小对象放到栈上优化
fn stacked_double(x: i32) -> i32 {
    let tmp = x * 2;   // 无需 Box
    tmp
}
```

### SA
```
// Box 版本：堆分配，Move 给调用者
@boxed_double(x: i32) -> ^ptr:
L_ENTRY:
    b = alloc 4
    v = mul x, 2
    store b+0, v as i32
    return ^b

// 栈版本：函数内局部缓冲，无需手动释放
@stacked_double(x: i32) -> i32:
L_ENTRY:
    tmp = stack_alloc 4
    v = mul x, 2
    store tmp+0, v as i32
    r = load tmp+0 as i32
    return r                       // stack_alloc 不允许 ^ 逃逸，只能返回值

@main:
L_ENTRY:
    result = call @boxed_double(5) // ^ptr 返回值
    !result                         // 前端必须 free
    return
```

**✅ 已修复**（v0.2 R2.1/P27）：`stack_alloc N` 生命周期绑定函数出口，禁止 `^ Move` 出函数（违反 → `Trap: StackEscape`）。消除了 Option 小值每次上堆的性能问题。

---

## 11. Enum + match（标签联合） ✅

### Rust
```rust
enum Shape {
    Circle(f32),
    Rectangle(f32, f32),
}

fn area(s: &Shape) -> f32 {
    match s {
        Shape::Circle(r) => 3.14159 * r * r,
        Shape::Rectangle(w, h) => w * h,
    }
}
```

### SA
```
#def Shape_SIZE     = 12
#def Shape_tag      = +0
#def Circle_r       = +4
#def Rect_w         = +4
#def Rect_h         = +8
#def TAG_CIRCLE     = 0
#def TAG_RECTANGLE  = 1

#def PI_F32 = 3.14159

@area(s: &Shape) -> f32:
L_ENTRY:
    tag = load s+Shape_tag as u32
    is_c = eq tag, TAG_CIRCLE
    br is_c -> L_CIRCLE, L_CHECK_RECT

L_CIRCLE:
    r = load s+Circle_r as f32
    rr = fmul r, r
    res_c = fmul PI_F32, rr
    return res_c

L_CHECK_RECT:
    is_r = eq tag, TAG_RECTANGLE
    br is_r -> L_RECT, L_MISS

L_RECT:
    w = load s+Rect_w as f32
    h = load s+Rect_h as f32
    res_r = fmul w, h
    return res_r

L_MISS:
    panic(106)     // PANIC_MissingVariant（R18.6 标准字典）
```

---

## 12. Option<T> / Result<T, E> ✅

### Rust
```rust
fn safe_div(a: i32, b: i32) -> Option<i32> {
    if b == 0 { None } else { Some(a / b) }
}
```

### SA（栈分配版本，v0.2）
```
#def Opt_tag = +0
#def Opt_val = +4
#def OPT_NONE = 0
#def OPT_SOME = 1

@safe_div(a: i32, b: i32) -> ^ptr:
L_ENTRY:
    is_zero = eq b, 0
    br is_zero -> L_NONE, L_SOME

L_NONE:
    r1 = alloc 8                   // 跨函数返回必须堆分配（栈值不能逃逸）
    store r1+Opt_tag, OPT_NONE as u32
    return ^r1

L_SOME:
    q = sdiv a, b
    r2 = alloc 8
    store r2+Opt_tag, OPT_SOME as u32
    store r2+Opt_val, q as i32
    return ^r2
```

**说明**：若 Option 仅在函数内使用（不作为返回值），则应用 `stack_alloc 8` 获得零堆开销。作为返回值必须 `alloc`。

---

## 13. `?` 错误传播 ✅

### Rust
```rust
fn load_config() -> Result<i32, u32> {
    let raw = read_file("config.txt")?;
    let parsed = parse_int(&raw)?;
    Ok(parsed * 2)
}
```

### SA
```
@extern read_file(path: &Str) -> ptr!
@extern parse_int(s: &Str) -> i32!

@const CONFIG_PATH: Str = utf8:"config.txt"    // v0.2 R6.5 全局常量

@load_config() -> i32!:
L_ENTRY:
    res1 = call @read_file(&CONFIG_PATH)
    raw  = ? res1                  // 展平见下方注释

    // Flattener 展平：
    // status1 = extractvalue res1, 0
    // ok1 = eq status1, 0
    // br ok1 -> L_CONT1, L_EARLY1
    // L_EARLY1:
    //     return res1              // 无须释放（无额外 Active 寄存器）
    // L_CONT1:
    //     raw = extractvalue res1, 1

    r_raw  = &raw
    res2   = call @parse_int(&r_raw)
    parsed = ? res2

    // L_EARLY2 此时 r_raw 和 raw 都 Active，必须在早返回前释放
    !r_raw
    !raw

    doubled = mul parsed, 2

    // 构造 Ok(doubled)
    ok_res = stack_alloc 8
    store ok_res+0, 0 as u32        // status = 0
    store ok_res+4, doubled as i32
    r = load ok_res+0 as u64        // 整体载入 2 字段作为 i32!
    return r
```

**✅ 已修复**（v0.2）：`@const CONFIG_PATH` 替代过去需要手动 `alloc + store` 字符串字面量的繁琐。Panic code 走标准字典（R18.6）。

**关键**：`?` 的 `L_EARLY*` 分支**前端必须**在每次早返回前释放所有存活寄存器，否则 `Trap: EarlyReturnLeak`（R18.7）。

---

## 14. 函数参数的三种模式 ✅

### Rust
```rust
fn by_value(x: i32) {}
fn by_borrow(r: &Data) {}
fn take_ownership(d: Data) {}
```

### SA
```
@by_value(x: i32):
    return

@by_borrow(r: &Data):
    return

@take_ownership(^d: ptr):
    !d
    return
```

---

## 15. 递归函数（链表遍历） ✅

### Rust
```rust
struct Node { val: i32, next: Option<Box<Node>> }

fn sum_list(node: Option<&Node>) -> i32 {
    match node {
        None => 0,
        Some(n) => n.val + sum_list(n.next.as_deref()),
    }
}
```

### SA
```
#def Node_val  = +0
#def Node_next = +8

@sum_list(node: ptr) -> i32:
L_ENTRY:
    br_null node -> L_NULL, L_BODY

L_NULL:
    return 0

L_BODY:
    r    = &node                   // 只读借用
    v    = load r+Node_val as i32
    next = load r+Node_next as ptr
    !r

    rest  = call @sum_list(next)
    total = add v, rest
    return total
```

---

## 16. 生命周期标注 `'a` ❌（刻意缺失）

### Rust
```rust
fn longest<'a>(x: &'a str, y: &'a str) -> &'a str {
    if x.len() >= y.len() { x } else { y }
}
```

### SA
```
@longest(x: &Str, y: &Str) -> &Str:
L_ENTRY:
    xlen = load x+Str_len as u64
    ylen = load y+Str_len as u64
    ge   = uge xlen, ylen
    br ge -> L_RET_X, L_RET_Y

L_RET_X:
    return x

L_RET_Y:
    return y
```

**❌ 刻意缺失**：SA 无生命周期类型系统。返回的 `&Str` 来源于 `x` 还是 `y`，SA 无法在类型层表达。

**这是 R20 前端合约的核心职责**：前端（smrustc）必须保证调用方在使用返回的 `&Str` 期间，对应源内存的借用锁未被 `!` 释放。`libsa_scope` helper 应提供辅助校验（仍是前端责任）。

**安全下限缺口**：前端降级错误时，不会在调用点立刻报错，可能产生悬空引用直到段错误。这是 SA 最需要警惕的一处。

---

## 17. 泛型 + 单态化 ✅

### Rust
```rust
fn max<T: PartialOrd>(a: T, b: T) -> T {
    if a >= b { a } else { b }
}
```

### SA（前端单态化后）
```
@max_i32(a: i32, b: i32) -> i32:
L_ENTRY:
    ge = sge a, b
    br ge -> L_A, L_B
L_A: return a
L_B: return b

@max_f32(a: f32, b: f32) -> f32:
L_ENTRY:
    ge = fcmp_ge a, b              // ✅ 已修复：R2.5 补齐 fcmp_ge
    br ge -> L_A, L_B
L_A: return a
L_B: return b
```

**✅ 已修复**（v0.2 R2.5）：`fcmp_ge` / `fcmp_le` / `fcmp_ne` 已补齐到 ISA。

---

## 18. Trait 静态分发 ✅（与泛型同）

### Rust
```rust
trait Area { fn area(&self) -> f32; }
impl Area for Circle { fn area(&self) -> f32 { 3.14 * self.r * self.r } }

fn print_area<T: Area>(s: &T) {}
```

### SA
```
#def Circle_r = +0

@Circle_area(self: &Circle) -> f32:
L_ENTRY:
    r = load self+Circle_r as f32
    rr = fmul r, r
    res = fmul 3.14, rr
    return res

@print_area_Circle(s: &Circle):
L_ENTRY:
    a = call @Circle_area(&s)
    call @print_f32(a)
    return
```

---

## 19. `dyn Trait` 动态分发（`@const` VTable） ✅

### Rust
```rust
trait Draw { fn draw(&self); }
impl Draw for Circle  { fn draw(&self) {} }
impl Draw for Square  { fn draw(&self) {} }

fn render(shapes: &[Box<dyn Draw>]) {
    for s in shapes { s.draw(); }
}
```

### SA（v0.2）
```
#def Dyn_data    = +0
#def Dyn_vtable  = +8
#def Dyn_SIZE    = 16

#def VT_draw     = +0
#def VT_drop     = +8
#def VTable_SIZE = 16

@Circle_draw(self: &Circle): return
@Square_draw(self: &Square): return
@Circle_drop(^c: ptr): !c; return
@Square_drop(^s: ptr): !s; return

// ✅ 已修复（v0.2 R6.5/R6.8）：全局只读 VTable
@const CIRCLE_VT: VTable_SIZE = vtable {
    draw = @Circle_draw,
    drop = @Circle_drop
}
@const SQUARE_VT: VTable_SIZE = vtable {
    draw = @Square_draw,
    drop = @Square_drop
}

@render(shapes: &Slice):
L_ENTRY:
    data_base = load shapes+Slice_data as ptr
    len       = load shapes+Slice_len  as u64
    i = 0
    jmp L_COND

L_COND:
    c = ult i, len
    br c -> L_BODY, L_END

L_BODY:
    off        = mul i, Dyn_SIZE
    elem       = ptr_add data_base, off        // InteriorPtr
    obj_data   = load elem+Dyn_data   as ptr
    obj_vtable = load elem+Dyn_vtable as ptr
    draw_fn    = load obj_vtable+VT_draw as ptr

    call_indirect draw_fn(obj_data)

    i = add i, 1
    jmp L_COND

L_END:
    return
```

**✅ 已修复**（v0.2）：
1. `@const ... : VTable_SIZE = vtable { ... }` 提供 rodata 段 VTable 构造（R6.5、R6.8）
2. `ptr_add` + `InteriorPtr` 消除气闸舱压力（R13.6）
3. VTable 被标为 `Immutable`（R4.8），禁止误 `!` 或 `&mut`

**未解决**：`call_indirect` 仍无法校验参数 ABI 一致性，这是 Rust 也有的痛点。

---

## 20. 闭包（Lambda Lifting） ✅

### Rust
```rust
fn main() {
    let multiplier = 3;
    let triple = |x: i32| x * multiplier;
    let result = triple(10);
}
```

### SA
```
#def Env_triple_multiplier = +0

@triple_impl(env: &Env_triple, x: i32) -> i32:
L_ENTRY:
    m = load env+Env_triple_multiplier as i32
    r = mul x, m
    return r

@main:
L_ENTRY:
    env = stack_alloc 4            // v0.2：闭包环境栈分配
    store env+Env_triple_multiplier, 3 as i32

    r_env  = &env
    result = call @triple_impl(&r_env, 10)
    !r_env

    return                          // stack_alloc 自动回收
```

---

## 21. Iterator + for 循环 ⚠️

### Rust
```rust
fn sum_squares(v: &Vec<i32>) -> i32 {
    v.iter().map(|x| x * x).sum()
}
```

### SA（前端展开迭代器链）
```
@sum_squares(v: &Vec) -> i32:
L_ENTRY:
    data = load v+Vec_data as ptr
    len  = load v+Vec_len  as u64
    s = 0
    i = 0
    jmp L_COND

L_COND:
    c = ult i, len
    br c -> L_BODY, L_END

L_BODY:
    off  = mul i, 4
    slot = ptr_add data, off
    x    = load slot+0 as i32
    sq   = mul x, x
    s    = add s, sq
    i    = add i, 1
    jmp L_COND

L_END:
    return s
```

**⚠️ 前端重担**：迭代器链的融合优化是 smrustc 的职责。SA 本身只看到展开后的单循环。

---

## 22. 原子操作（`atomic_rmw_*` + `cmpxchg` 双返回） ✅

### Rust
```rust
use std::sync::atomic::{AtomicI32, Ordering};

fn increment(c: &AtomicI32) {
    c.fetch_add(1, Ordering::SeqCst);
}

fn try_swap(c: &AtomicI32, expected: i32, new: i32) -> bool {
    c.compare_exchange(expected, new, Ordering::AcqRel, Ordering::Acquire).is_ok()
}
```

### SA（v0.2）
```
@increment(c: &i32):
L_ENTRY:
    // ✅ 已修复（R2.1 atomic_rmw 族）：单条指令原子 fetch_add
    old = atomic_rmw_add c+0, 1 seq_cst
    return

@try_swap(c: &i32, expected: i32, new: i32) -> i32:
L_ENTRY:
    // ✅ 已修复（R2.1/R2.7 + P29）：cmpxchg 双返回值 (old, ok)
    old, ok = cmpxchg c+0, expected, new acq_rel acquire
    // ok 是 i1 布尔；转成 i32 返回
    ret = zext ok
    return ret
```

**✅ 已修复**（v0.2）：
- `atomic_rmw_{add,sub,and,or,xor,xchg,smin,smax,umin,umax}` 指令族 1 条完成原子 RMW（R2.1）
- `cmpxchg` 返回 `(old_value, ok: i1)` 双值（R2.7、P29）
- ordering 支持 `seq_cst` / `acq_rel` / 双 ordering（success / failure）

---

## 23. async/await（状态机展平） ⚠️

### Rust
```rust
async fn fetch_and_parse(url: &str) -> Result<i32, u32> {
    let data = fetch(url).await?;
    let parsed = parse(&data).await?;
    Ok(parsed)
}
```

### SA（前端 CPS 转换后，省略细节）
```
#def State_state   = +0
#def State_url     = +8
#def State_url_len = +16
#def State_data    = +24

@fetch_and_parse_poll(ctx: &State) -> i32!:
L_ENTRY:
    state = load ctx+State_state as u32
    is_init = eq state, 0
    br is_init -> L_INIT, L_CHECK_FETCH

L_INIT:
    // 发起 fetch，注册到外部 reactor
    // ...
    store ctx+State_state, 1 as u32
    return_pending

// ... L_CHECK_FETCH / L_RESUME_FETCH / L_CHECK_PARSE / L_DONE
```

**⚠️ 前端重担**（未变）：
- CPS 转换约 3000 行前端代码量
- 每个 `await` 点 = 新 state ID + 检查 Label
- 局部变量跨 `await` 必须存进 ctx（栈会被切走）

**建议**：`libsa_scope` 扩展出 `libsa_async` helper，或在 v0.3 考虑 coroutine 原语（但会破坏扁平性）。

---

## 24. Rc/Arc 引用计数（`atomic_rmw_sub`） ✅

### Rust
```rust
use std::sync::Arc;

fn main() {
    let a = Arc::new(42i32);
    let b = a.clone();    // strong_count = 2
    let c = a.clone();    // strong_count = 3
    // 离开作用域：原子递减到 0 时 free
}
```

### SA（v0.2）
```
#def Rc_strong    = +0
#def Rc_weak      = +8
#def Rc_value_i32 = +16
#def Rc_TOTAL_i32 = 20

@rc_new_i32(v: i32) -> ^ptr:
L_ENTRY:
    r = alloc Rc_TOTAL_i32
    store r+Rc_strong, 1 as u64
    store r+Rc_weak, 1 as u64
    store r+Rc_value_i32, v as i32
    return ^r

// Clone: 原子递增 strong
@rc_clone(r: &ptr) -> ^ptr:
L_ENTRY:
    r_addr = load r+0 as ptr
    // ✅ 已修复：单条原子 RMW
    old = atomic_rmw_add r_addr+Rc_strong, 1 acq_rel
    // 直接把同一指针作为新的所有权副本返回
    // （前端保证调用方处理好 Move 语义）
    return ^r_addr

// Drop: 原子递减，到 1→0 时 free
@rc_drop(^r: ptr):
L_ENTRY:
    // ✅ 原子 fetch_sub 返回旧值；若旧值 == 1 则此次是最后一个引用
    old = atomic_rmw_sub r+Rc_strong, 1 acq_rel
    is_last = eq old, 1
    br is_last -> L_FREE, L_DONE

L_FREE:
    !r                              // 物理 free
    return

L_DONE:
    return
```

**✅ 已修复**（v0.2）：用 `atomic_rmw_add` / `atomic_rmw_sub` 一条指令完成，无需 `cmpxchg` retry loop，真正满足原子语义。

---

## 25. unsafe 块与裸指针（气闸舱） ✅

### Rust
```rust
extern "C" {
    fn c_sum(ptr: *const i32, len: usize) -> i32;
}

fn call_c_sum(arr: &[i32]) -> i32 {
    unsafe { c_sum(arr.as_ptr(), arr.len()) }
}
```

### SA
```
@extern c_sum(ptr: *i32, len: u64) -> i32

@ffi_wrapper call_c_sum(arr: &Slice) -> i32:
L_ENTRY:
    data_base = load arr+Slice_data as ptr
    len       = load arr+Slice_len  as u64

    // 裸指针降级：只在气闸舱内允许
    raw_ptr   = *data_base
    res       = call @c_sum(raw_ptr, len)
    return res
```

**说明**：
- **普通函数**出现 `*` / `assume_*` → `Trap: IllegalUnsafeContext`（R13.5）
- FFI 调用链顶必须 `@ffi_wrapper`
- 比 Rust 的 `unsafe { }` 块更严格（函数级而非块级）

**注意 `InteriorPtr` 与裸指针的区别**：
- `ptr_add` 派生的 `InteriorPtr` 只能在本函数内 `load`/`store`
- 若要把它传给 `@extern`，必须先在 `@ffi_wrapper` 内用 `*` 再降级（否则 `Trap: InteriorPtrEscape`，R13.7）

---

## 26. FFI extern "C" ✅

### Rust
```rust
#[no_mangle]
pub extern "C" fn sa_multiply(a: i32, b: i32) -> i32 {
    a * b
}
```

### SA
```
@export sa_multiply(a: i32, b: i32) -> i32:
L_ENTRY:
    r = mul a, b
    return r
```

---

## 27. panic! / panic_msg ✅

### Rust
```rust
fn divide(a: i32, b: i32) -> i32 {
    if b == 0 { panic!("div by zero"); }
    a / b
}

fn slice_check(arr: &[i32], i: usize) -> i32 {
    if i >= arr.len() {
        panic!("index {} out of {} bounds", i, arr.len());
    }
    arr[i]
}
```

### SA（v0.2）
```
// 标准 panic code 字典（R18.6）
#def PANIC_DIV_BY_ZERO   = 100
#def PANIC_OUT_OF_BOUNDS = 101

// 字符串消息放 rodata
@const MSG_DIV_BY_ZERO: Str = utf8:"div by zero"

@divide(a: i32, b: i32) -> i32:
L_ENTRY:
    z = eq b, 0
    br z -> L_PANIC, L_OK

L_PANIC:
    // ✅ 已修复（R18.5）：panic_msg 携带消息
    r_msg = &MSG_DIV_BY_ZERO
    data  = load r_msg+Str_data as ptr
    len   = load r_msg+Str_len  as u64
    panic_msg(PANIC_DIV_BY_ZERO, data, len)

L_OK:
    q = sdiv a, b
    return q
```

**✅ 已修复**（v0.2 R18.5）：`panic_msg(code, *str_ptr, str_len)` 携带消息字符串。Native 写 stderr 再 `_exit`；WASM `fd_write(2,...)` 再 `unreachable`。标准 panic code 字典见 R18.6。

---

## 28. `#mode compact` 紧凑中缀糖（v0.2 可选） ✅

### Rust
```rust
fn dot(a: &[f32; 3], b: &[f32; 3]) -> f32 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}
```

### SA（默认关键字形态）
```
@dot(a: &Vec3, b: &Vec3) -> f32:
L_ENTRY:
    ax = load a+0 as f32
    ay = load a+4 as f32
    az = load a+8 as f32
    bx = load b+0 as f32
    by = load b+4 as f32
    bz = load b+8 as f32
    m1 = fmul ax, bx
    m2 = fmul ay, by
    m3 = fmul az, bz
    s1 = fadd m1, m2
    s2 = fadd s1, m3
    return s2
```

### SA（`#mode compact` 形态）
```
#mode compact

@dot(a: &Vec3, b: &Vec3) -> f32:
L_ENTRY:
    ax = load a+0 as f32
    ay = load a+4 as f32
    az = load a+8 as f32
    bx = load b+0 as f32
    by = load b+4 as f32
    bz = load b+8 as f32
    m1 = ax * bx
    m2 = ay * by
    m3 = az * bz
    s1 = m1 + m2
    s2 = s1 + m3
    return s2
```

**重要约束**（R24.3）：
- ❌ 不能写 `s = ax * bx + ay * by + az * bz`（禁止多操作符组合）
- ❌ 不能写 `s = a < b`（禁止中缀比较）
- ❌ 不能写 `s = a && b`（无短路）
- ✅ 只能单行一个中缀操作符

**P30 保证**：启用前后的源码，Flattener 产出的 `Instruction[]` 必须字段级相等。

---

# 压力测试总结（v0.2 规范对齐）

## 设计评分

| 维度 | v0.1 评分 | v0.2 评分 | 证据 |
|---|---|---|---|
| 基础控制流降级 | ✅ | ✅ | 案例 1-5 |
| 所有权与借用 | ✅ | ✅ | 案例 3-5 |
| 错误传播 | ✅ | ✅ | 案例 12-13 |
| 结构体与 Enum | ✅ | ✅ | 案例 6, 11 |
| 原子操作 | ⚠️ 缺 RMW | ✅ | 案例 22, 24（R2.1 补齐） |
| 泛型与 Trait | ✅ | ✅ | 案例 17-18 |
| 动态分发 / VTable | ⚠️ 缺 rodata | ✅ | 案例 19（R6.5/R6.8 补齐） |
| 生命周期类型系统 | ❌ 刻意缺失 | ❌ 刻意缺失 | 案例 16 |
| 切片/字符串索引 | ⚠️ 推气闸 | ✅ | 案例 2, 7, 8, 9（R13.6 `InteriorPtr`） |
| async/await | ⚠️ 前端重担 | ⚠️ 前端重担 | 案例 23 |
| FFI / unsafe | ✅ | ✅ | 案例 25-26 |
| Box / Rc / Arc | ⚠️ 缺 stack_alloc / rmw | ✅ | 案例 10, 24 |
| panic 语义 | ⚠️ 无消息 | ✅ | 案例 27（R18.5 `panic_msg`） |
| **Token 密度（可选）** | — | ✅ `#mode compact` | 案例 28 |

## v0.1 到 v0.2 的缺口修复总览

| 缺口 | v0.2 修复 | Requirements |
|---|---|---|
| 切片索引被迫进气闸舱 | `ptr_add` + `InteriorPtr` 状态位 | R2.5, R4.9, R4.10, R13.6 |
| VTable 无处安放 | `@const NAME: T = vtable {...}` | R6.5, R6.8 |
| 原子 RMW 要 cmpxchg 循环 | `atomic_rmw_{add,sub,...}` 指令族 | R2.1 |
| `cmpxchg` 无成功位返回 | 双返回值 `(old, ok)` | R2.7, P29 |
| 浮点比较缺 `ge/le/ne` | ISA 补齐 | R2.5 |
| Option 小值每次堆分配 | `stack_alloc N` | R2.1, P27 |
| panic 无消息 | `panic_msg(code, *s, len)` | R18.5 |
| panic code 五花八门 | 标准字典 100-107 | R18.6 |
| 算术写法冗余（可选） | `#mode compact` 中缀糖 | R24 |

## smrustc 前端工作量更新

基于修复后的 SA，前端代码量估算：

| 阶段 | v0.1 估算 | v0.2 估算 | 变化原因 |
|---|---|---|---|
| 案例 1-10 基础 | 500-1000 行 | 400-800 行 | `InteriorPtr` 消除气闸舱包装 |
| 案例 11-18 中级 | +1500 行 | +1300 行 | `@const` 简化字面量处理 |
| 案例 19-22 高级 | +2000 行 | +1500 行 | VTable/`atomic_rmw` 简化 |
| 案例 23 async | +3000 行 | +3000 行 | 未变（CPS 转换本质复杂） |
| 案例 24-27 其它 | +500 行 | +400 行 | panic_msg / stack_alloc 简化 |
| **总计** | **~7500-8000 行** | **~6600-7000 行** | 净减 ~1000 行 |

## 结论：SA v0.2 能不能用来重写 Rust 项目？

**能，且比 v0.1 显著更顺滑。**

关键缺口都已对齐：
- `InteriorPtr` 让日常 `arr[i]` 不再逃进 unsafe
- `@const` 让 VTable/字符串字面量有正式家
- `atomic_rmw` / `cmpxchg` 双返回值让并发原语语义完整
- `stack_alloc` 让小对象不再强制堆分配
- `panic_msg` + 标准字典让错误可诊断
- `#mode compact`（可选）让手写 SA 不必被关键字淹没

**仍然保留的刻意缺失**：
- 生命周期类型系统（R20 前端合约承担）
- async/await 原生支持（CPS 由前端做）
- 操作符优先级（紧凑糖仍禁止组合）

SA 的核心哲学——"把证明外包给 Referee 的 O(1) 位掩码"——在 v0.2 后站得更稳。**前端责任制是真实成本**，但比官方 rustc 的借用检查器数十万行代码轻量一个数量级。
