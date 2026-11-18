# fast-math 编译开关 — 实现与验证（完整）

日期：2026-11-18
分支：wasm（sci 隔离副本）
状态：实验性功能，代码已改，待审核

## 一、结论

实现了 `--fast-math` 编译开关（默认关闭），给 LLVM 的 fadd/fmul/fsub/fdiv 加 `fast` 标记，使 LLVM 能向量化浮点归约循环。实测 matmul **778ms → 317ms（2.45×）**，SLA 路径 817ms → 307ms（2.66×）。默认关闭时行为完全不变。

## 二、改动清单（5 个文件）

1. **`src/emit_options.zig`**：`EmitOptions` 加 `fast_math: bool = false`
2. **`src/cli.zig`**：
   - `CompileOptions` 加 `fast_math: bool = false`
   - `consumeCompileOption` 解析 `--fast-math`
   - 6 处 `emit_llvm_llvmc.emit*` 调用传 `.fast_math = compile_options.fast_math`
3. **`src/emit_llvm_llvmc.zig`**：`CModule` extern struct 加 `fast_math: bool` 字段（与 C 侧布局一致）；2 处 CModule 初始化传 `options.fast_math`
4. **`src/emit_llvm_llvmc_shim.c`**：
   - `SaModule` 加 `fast_math` 字段
   - `EmitCtx` 加 `fast_math` 字段，`build_sa_llvm_module` 从 m 传递
   - 通过 LLVM 14 的 C++ 符号 `llvm::Instruction::setFast(bool)`（mangled: `_ZN4llvm11Instruction7setFastEb`，已验证可用）给浮点指令加 fast 标记
   - `sa_fast_float(fast_math, v)` helper，仅在开关打开时调用

## 三、验证结果（实际跑测试）

### 功能对照（同一 .sa，best-of-5）
| 路径 | 默认 | --fast-math | 提升 |
|---|---:|---:|---:|
| sa 直接编译 matmul | 778 ms | **317 ms** | 2.45× |
| SLA 委托 sa 编译 matmul | 817 ms | **307 ms** | 2.66× |

### IR 证据
- 默认：`fmul fast=0`（无标记）
- `--fast-math`：`fmul fast=1`，LLVM 生成 `<2 x double>` SIMD + `llvm.vector.reduce.fadd`

### 回归测试
- `emit_options.zig` 单测：1 passed
- 默认编译 3 个 demo（01_hello/03_if_else/04_loop）：全部正常（hello,saasm / 20 / [0,0,0,0]）

## 四、技术要点

1. **LLVM 14 无 C API 设置 fast-math**：用 mangled C++ 符号调用 `llvm::Instruction::setFast(bool)`，shim 虽是 C 文件但通过 extern mangled name 调用可行（独立实验验证 IR 出现 `fadd fast`）。
2. **字段布局对齐**：`SaModule`(C) 与 `CModule`(Zig extern struct) 的 `fast_math` 字段位置必须一致，否则内存布局错乱。
3. **缓存陷阱**：sa 的项目缓存会命中旧的 bc。测试必须用 `--no-incremental` 或清缓存，否则新 flag 不生效。同理，产品化时需把 `fast_math` 折进缓存 key。

## 五、风险与未完成项（诚实）

1. **浮点语义改变**：fast-math 允许重结合/假设无 NaN/Inf，科学计算或需要 IEEE 严格语义的程序不能开。默认关闭规避。
2. **缓存 key 未包含 fast_math**：目前开/关可能命中同一缓存条目（需 `--no-incremental` 才可靠）。产品化前必须把 fast_math 折进 `computeProjectBuildKey`。
3. **仅覆盖二元浮点运算**：fneg/fcmp/类型转换等未加标记（影响小）。
4. **SLA 透传**：SLA 的 `--fast-math` 能透传（已验证），但 SLA 自己的 CLI help/文档未更新。
5. **ABI 符号调用**：依赖 LLVM 14 的 C++ mangled 符号 `_ZN4llvm11Instruction7setFastEb`，LLVM 升级可能变（需在 CI 锁定 LLVM 14）。

## 六、与 Rust 的剩余差距

开了 fast-math 后 307ms vs Rust 19ms，仍有 16× 差距。来自：SSE `<2 x double>` vs AVX `<4 x double>`（未设 target-cpu=native）、循环优化激进度、内存访问模式。fast-math 拿回了最大一块（2.5×）。

## 七、建议

- 这是一个**明确、可控、高 ROI** 的运行时优化（几行核心逻辑 + 2.5×）
- 产品化前需完成：缓存 key 隔离、CLI help 文档、CI 锁 LLVM 版本
- 已在隔离分支 wasm，未碰主仓 sci

## 八、状态

代码改动在 sci-wasm/wasm 分支，已本地验证，待审核后提交推送。实验产物在 /tmp/{fm_off,fm_on,mm_sla_fm}.*。
