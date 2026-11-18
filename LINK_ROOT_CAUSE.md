# build-wasm link 阶段根因分析（实测）

日期：2026-11-18
分支：wasm（隔离实验区）

## 一、根因：link 80ms 的完整分解（best-of-7 实测）

| 环节 | 时间 | 说明 |
|---|---:|---|
| `zig cc --version`（纯驱动启动） | **33 ms** | zig cc 驱动层固定税，与链接内容无关 |
| link `.sa.bc`（无 archive） | 52 ms | = 启动 33 + wasm-ld 链接 19 |
| link `.sa.bc` + 7.3MB archive | 80 ms | = 启动 33 + wasm-ld 19 + **解析 archive 28** |

**结论**：78-80ms 的 link 由三块构成——驱动启动 33ms（42%）、archive 解析 28ms（35%）、wasm-ld 链接 19ms（24%）。

## 二、关键旁证

1. **产物 99.8% 是 debug**：plain 产物 1.25MB，`--strip-debug` 后 1.8KB；code section 仅 1.6KB。说明 wasm-ld 已经把未用函数丢弃了。
2. **`--gc-sections` 显式加无效**：产物 code 只有 1.6KB，wasm-ld 默认已做 section GC，加 flag 无额外收益。
3. **archive 是单 compilation unit**：`sa_std_zcu.o` 一个 object 含 8009 函数。wasm-ld 必须全量解析它的符号表 + reloc（即便只 pull 1.6KB 代码），这是 28ms 的来源。

## 三、三个攻击面（按 ROI）

| 方案 | 可省 | 难度 | 风险 |
|---|---:|---|---|
| **A. 拆 sa_std 为多个 object**（按模块分组，让 archive 按需 pull） | ~28ms | 中（改 build.zig 模块拆分） | 需保证 linker 语义不变 |
| **B. 绕开 zig cc 驱动层**（直接调 zig 内嵌 lld / 常驻 linker） | ~33ms | 高（zig 无独立 wasm-ld，需研究内嵌 lld 调用） | ABI/参数兼容性 |
| **C. wasm 模块动态链接**（sa_std 预实例化，import 代替静态链接） | ~28+19ms | 高（改运行时模型） | WASI 支持、体积/启动权衡 |

`build.zig:162` 已有 `link_function_sections = true`，但单 object 下 section GC 仍需解析整个 object——拆分 object 是关键。

## 四、下一步建议

先做 **A（拆 object）**：它最可控、收益明确（28ms / 35%）。做法是将 `sa_std.zig` 按顶层模块拆成多个 root source，各自编译为独立 object 再 ar 打包，使 wasm-ld 只解析被引用的 object。

B（绕开 zig cc）作为后续，需先调研 zig 是否暴露内嵌 lld 的可调用入口（当前无独立 wasm-ld 二进制）。

## 五、与 MoonBit 的差距归因

MoonBit 18ms vs SA link 80ms（+前端/启动 ~20ms = 100ms）：
- 33ms 是 zig cc 驱动税（MoonBit 自有编译器无此）
- 28ms 是单 object archive 解析（MoonBit 用预编译 .mi，无静态链接）
- 19ms wasm-ld + ~20ms 前端/启动

要追平必须同时动 A + B（省 61ms），把 SA 压到 ~40ms 才接近 2× 差距。
