# SA 默认不可变动态开关评估

## 背景

SA 语言当前能力模型中，`reg = alloc N` 默认进入 `Active` 状态 (默认可变)。该评估探讨将默认行为改为 `Active + Immutable` (Rust 风格 `let x = ...` 默认不可变) 的可能性，以及通过**动态开关** `--default-immutable` 实现向后兼容。

## 评估结论

**YES — SA 天然支持运行期动态开关。** 编译器后段仅需约 5-10 行变更，sa_std 无须大批量迁移即可保持当前行为。开启开关后 sa_std 需要 `=&`/`!` 借用模式迁移 (预估 500-1500 行)。

---

## 1. 核心机制已就绪

### 1.1 Immutable 位已完整实现

**`src/common/capability.zig:3`** (CapabilityMask 枚举):

```zig
pub const CapabilityMask = enum(u16) {
    uninitialized = 0x00,
    active = 0x01,
    locked_read = 0x02,
    locked_mut = 0x04,
    consumed = 0x08,
    immutable = 0x0100,    // 已存在, 目前仅 @const 使用
};
```

TRUTH_TABLE 已包含 Immutable 组合条目 (`src/common/capability.zig:66-84`):

```
.{ .prev_mask = 0x00, .op = .alloc, .legal = true, .new_mask = 0x101, .trap = null },  // Active|Immutable
```

### 1.2 verifier.zig 中的 Immutable 写保护

**`src/verifier.zig:511`**:

```zig
const regFlagImmutable: u8 = 0x04;

fn isImmutable(mask: u16) bool {
    return (mask & maskOf(.immutable)) != 0;
}

fn isImmutableConst(state: []const u16, flags: []const u8, id: u32) bool {
    return isImmutable(state[idx]) or (flags[idx] & regFlagImmutable) != 0;
}
```

`writeCheck` (**`src/verifier.zig:2678`**) 拒绝对 Immutable 寄存器的 `store`:

```zig
fn writeCheck(item, function_text, is_ffi_wrapper, name, id, state, flags, origins, locks) ?TrapReport {
    if (readCheckAllowRaw(...)) |tr| return tr;  // Immutable 写保护在此被拒
}
```

### 1.3 Immutable 位的行为保障

| 操作 | Immutable 时触发 | 代码位置 |
|---|---|---|
| `store` | `ConstMutation` trap | `writeCheck` (verifier.zig:2678) |
| `^move` | `ConstMutation` trap | move handler |
| `!release` | `ConstMutation` trap | release handler |
| `&mut` 独占借用 | `ConstMutation` trap | borrow handler |

Immutable 位**只影响写操作**，`load`/`ptr_add`/共享借用 `&reg` 完全不受影响。

---

## 2. Patch 方案

### 2.1 CLI 层 (`src/cli.zig`)

在 `CompileOptions` / `VerifyOptions` 新增字段:

```zig
// src/cli.zig (添加到 CompileOptions 结构体)
const VerifyOptions = struct {
    // existing fields ...
    default_immutable: bool = false,  // 新增: 默认 false (向后兼容)
};
```

CLI flag:

```
sa check --default-immutable source.sa
sa build-exe --default-immutable source.sa
```

### 2.2 能力位层 (`src/common/capability.zig`)

TRUTH_TABLE 补充 1 条 `release_own` 条目, 使 Immutable 寄存器释放时合法 (L82 之后):

```
.{ .prev_mask = 0x101, .op = .release_own, .legal = true, .new_mask = 0x00, .trap = null },
```

| Prev Mask | Op | Legal | New Mask | 说明 |
|---|---|---|---|---|
| 0x101 (Active|Immutable) | release_own | true | 0x00 (Uninitialized) | Immutable 寄存器释放为 Uninitialized |

### 2.3 验证器层 (`src/verifier.zig`)

#### alloc handler (**`src/verifier.zig:3359-3369`**):

```diff
.alloc => {
-    if (assignValue(item, ..., maskOf(.active), &interior)) |tr| return tr;
+    const default_mask: u16 = if (opts.default_immutable)
+        maskOf(.active) | maskOf(.immutable)    // 0x101
+    else
+        maskOf(.active);                        // 0x01
+    if (assignValue(item, ..., default_mask, &interior)) |tr| return tr;
}
```

#### stack_alloc handler (**`src/verifier.zig:3370-3380`**):

同模式:

```diff
.stack_alloc => {
+    const default_mask: u16 = if (opts.default_immutable)
+        maskOf(.active) | maskOf(.immutable)
+    else
+        maskOf(.active);
     if (assignValue(item, ..., default_mask, &interior)) |tr| return tr;
}
```

#### load 传播 Immutable 位

`load` 操作从 Immutable 寄存器读取时应传播 Immutable 位 (`src/verifier.zig:3381-3392`):

```diff
.load, .take => {
    if (readCheck(item, ..., item.operands[1].reg, state, flags)) |tr| return tr;
+    const src_immutable = isImmutableConst(state, flags, item.operands[1].reg);
+    const new_mask: u16 = if (src_immutable) maskOf(.active) | maskOf(.immutable) else maskOf(.active);
+    if (assignValue(item, ..., new_mask, &interior)) |tr| return tr;
}
```

### 2.4 emit_llvm_llvmc.zig: 零改动

`src/emit_llvm_llvmc.zig` (1984 行) 不感知 Capability Mask, 仅发射 LLVM 操作。Immutable 位对 LLVM-C 发射器**完全透明**。

### 2.5 interp.zig: 零改动

`src/interp.zig` (2344 行) 不检查 capability mask, 解释执行时同样不受影响。

---

## 3. 行为验证基线

| 场景 | default-mutable (当前) | default-immutable (新开关) |
|---|---|---|
| `reg = alloc N` | Active (0x01) | Active|Immutable (0x101) |
| `store reg+0, val` | 执行 | ConstMutation trap |
| `load reg+0` | 只读 | 只读 (Immutable 允许 load) |
| `&reg` (共享借用) | 通过 | 通过 (Immutable 可共享借用) |
| `=&reg` (独占借用) | 通过 | ConstMutation |
| `^reg` (move) | 通过 | ConstMutation |
| `!reg` (release) | 通过 | 通过 (TRUTH_TABLE 补充后) |

---

## 4. sa_std 迁移影响

### 量况

- `sa_std/` 共 92 个 `.sa`/`.sal` 文件
- `tests/` 下约 226 个 `.sa`/`.sal` fixture 文件
- sa_std 约有 8,862 个 `[MACRO]` 定义
- 每个宏平均 3-5 处 `store` 操作, 约 1,500-2,500 处 store

### 当前 sa_std store 模式 (以 `sa_std/alloc/vec.sa` 为例)

```sa
vec = alloc Vec_SIZE          # alloc -> Active (可变)
store vec+Vec_ptr, 0 as ptr   # store 原样执行
store vec+Vec_cap, cap as u64 # store 原样执行
!vec = ...                    # release
```

### 迁移后 (default-immutable 模式)

```sa
vec = alloc Vec_SIZE          # alloc -> Active | Immutable (不可变)
=&vec                          # 独占借用 -> locked_mut  (需显式声明可变)
store vec+Vec_ptr, 0 as ptr   # store 通过 (locked_mut 状态)
store vec+Vec_cap, cap as u64 # store 通过
!vec = ...                    # release borrow
!vec                           # release allocation
```

### 迁移策略

**选项 A**: sa_std 内部新增 `MUTABLE_STORE` 宏抽象层:

```
#def MUTABLE_STORE dst_offset, val = =&dst ... store dst+offset, val ... !dst
```

**选项 B**: 直接在宏体内插入 `=&`/`!` 对, 更清晰但需人工 review。

**估算**: 约 500-1,500 行 `.sa` 代码 需要手动迁移到 `=&`/`!` borrow 模式。

---

## 5. 向后兼容性

| 模式 | 默认行为 | sa_std 兼容性 | 说明 |
|---|---|---|---|
| `--default-mutable` | alloc -> Active | 原样 | 当前默认行为, 既有代码零改动 |
| `--default-immutable` | alloc -> Active|Immutable | 需要迁移 | 新模式, store 操作必须加 `=&` 借用 |

### 函数级开关 (stretch)

`VerifyOptions` 可记录每个函数是否开启 immutable, 实现函数级开关:

```zig
default_immutable_per_func: std.StringHashMap(bool) = .{},
```

sa_std 可在模块顶通过 `#def` 或属性声明函数级可变性。

---

## 6. 验证 PoC 建议

1. **Patch 编译器**: 应用 §2.1-2.3 的变更
2. **编译**: `zig build` (需 LLVM header, 否则 `zig build -Dllvm=false`)
3. **跑验证**:
   ```
   # 1. 基线: default-mutable 模式 sa_std 原样通过
   sa check --profile sa_std sa_std/alloc/vec.sa
   
   # 2. default-immutable 模式: 观察 ConstMutation trap 分布
   sa check --profile sa_std --default-immutable sa_std/alloc/vec.sa
   ```
4. **预期结果**: 开启 `--default-immutable` 后, sa_std 的 store 操作触发 `ConstMutation` (trap 1036), 给出确切迁移计数。

---

## 7. 总结

| 变更 | 行数 | 风险 | 说明 |
|---|---|---|---|
| CLI flag + VerifyOptions | ~10 行 | 低 | 新增 default_immutable 字段 |
| TRUTH_TABLE +1 条 | 1 行 | 低 | release_own for Immutable |
| verifier.alloc/stack_alloc | 2×3=6 行 | 中 | 条件分支 + opts 传导 |
| verifier.load Immutable 位传播 | ~3 行 | 中 | 确保派生指针继承 Immutable |
| sa_std 迁移 | 500-1500 行 | 高 | store 操作需加 =&/! 借用 |

**动态开关 `--default-immutable` 是 SA 默认不可变 (Rust-adaptive) 提案的最小可行实现。** 仅 10-15 行编译器变更即可实现功能开关；sa_std 需要相应 `=&`/`!` 借用模式迁移才能兼容。

SA 设计层面**天然支持不可变优先** —— 将 `alloc` 的初始 mask 添加 `| immutable` 位即可激活默认不可变模式; 现有 Immutable 位写保护设施 (writeCheck/const_mutation trap) 无需任何新增 Trap。

---

## 参考文件位置

| 组件 | 文件路径 | 关键行号 |
|---|---|---|
| CapabilityMask 枚举 | `src/common/capability.zig:3` | 3-15 |
| TRUTH_TABLE | `src/common/capability.zig:66-84` | 66-84 |
| regFlagImmutable | `src/verifier.zig:511` | 511 |
| isImmutable / isImmutableConst | `src/verifier.zig:556-562` | 556-562 |
| alloc handler | `src/verifier.zig:3359` | 3359-3369 |
| stack_alloc handler | `src/verifier.zig:3370` | 3370-3380 |
| load handler | `src/verifier.zig:3381` | 3381-3392 |
| writeCheck | `src/verifier.zig:2678` | 2678-2695 |
| VerifyOptions | `src/cli.zig:~7682` | 约 L7682 |
| LLVM-C Emitter | `src/emit_llvm_llvmc.zig` | 1984 行, 零改动 |
| 解释器 | `src/interp.zig` | 2344 行, 零改动 |
| sa_std 示例 | `sa_std/alloc/vec.sa` | L8-12 |