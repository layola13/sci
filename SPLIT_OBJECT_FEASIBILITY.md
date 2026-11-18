# 拆 sa_std object 可行性验证（方案 A）

日期：2026-11-18
分支：wasm

## 一、验证结论

**技术可行，但工程摩擦高于预期，ROI 存疑。**

## 二、实测证据（全部 best-of-7）

### 2.1 wasm-ld 解析时间随 object 大小增长
| object | 大小 | link 时间 |
|---|---:|---:|
| 100 函数 | 13 KB | 43.4 ms |
| 1000 函数 | 124 KB | 46.3 ms |
| 8000 函数 | 1 MB | 70.2 ms |

### 2.2 archive 按需 pull 有效
| 场景 | link 时间 |
|---|---:|
| 单个大 object 直接链接 | 68.5 ms |
| archive（大+小），引用符号在小 object，大 object 不被 pull | **56.8 ms**（省 12ms） |

### 2.3 裁剪发生在解析之后
产物只有 16 个函数、1.6KB code（8009 函数里 99.8% 被裁），但 wasm-ld 仍花 28ms 全量解析 7.3MB object 的符号表 + reloc。拆 object 的价值就是让 linker **根本不解析**无用 object。

## 三、工程摩擦（验证中发现）

1. **源码级拆分需改 28 个 satellite**：sa_std.zig 有约 300 行 `comptime { _ = &@import("sa_*.zig").func; ... }` 强制引用块，把这些卫星的 export fn 拉进主 object。拆分必须删除这些引用（否则符号重复定义），再在 build.zig 把每个 satellite 单独编译成 object 并 `addObjectFile`。
2. **satellite 依赖不完全独立**：虽然大多只依赖 std/sio/builtin，但有 peer 依赖（sa_http_server → sa_ws_stream），需要按拓扑顺序编译。
3. **单 satellite 编译摩擦**：尝试单独编译 sa_toml.zig 时，Zig 0.17 报 `module "sio" declared but not used`（sio 引用在 target 条件分支里，wasi 下被消除）。需要额外的 import 对齐工作。
4. **native archive 必须保持字节不变**：拆分只应作用于 wasi，native 构建不能受影响（调试体验 + 兼容性）。

## 四、JEV 决策（两次）

- 第一次（拆 object vs 绕 zig cc）：选 b（绕驱动），置信度 44%
- 第二次（新证据：绕驱动破坏 WASI `_start` 入口语义，实测只省 16-26ms）：改选 a（拆 object），置信度 41%，d（低风险验证）44%

两次置信度都在 40% 区间，说明**没有明显赢家**。

## 五、方案 B（绕开 zig cc）的验证结果（供对比）

- `zig version` 启动 6.8ms，`zig cc --version` 28ms，`zig build-exe --help` 7.5ms → 绕开 cc 理论上省 ~20ms
- `zig build-exe` 直接链接 .sa.bc + archive：54-64ms（vs zig cc 80ms），但：
  - `-fno-entry` → 产物无 `_start`，wasmtime 不执行 main（空模块）
  - `-lc` → 有 `_start` 但调用未定义的 `main`，trap
  - WASI 入口重映射复杂、风险高

## 六、建议

两条路都有明显摩擦：
- A（拆 object）：收益 12-28ms，需改 28 卫星 + 300 行引用块 + 依赖拓扑，工程量大
- B（绕驱动）：收益 16-26ms，但破坏 WASI 入口语义，需重建 `_start` 映射，风险高

**建议暂停大改动**。已交付的两项（构建时 strip + 链接时 --strip-debug）已省下 link 的大头（204→80ms，产物 5.5MB→1.8KB），继续攻剩余 28ms 的 ROI 不高。

如果要继续，建议先做 A 的最小验证：只拆 1-2 个卫星（如 sa_toml/sa_yaml），确认符号不重复、link 更快，再决定是否扩展到 28 个。但即使全部拆完，SA ~100ms vs MoonBit 18ms 的 5× 差距仍在——那是架构性差异（外部链接阶段）。

## 七、当前分支状态

- 已提交：04fd392d(构建strip) / 7cb38734(链接strip-debug) / 清理提交 / LINK_ROOT_CAUSE.md
- 本文档记录探索结论，未改 build.zig / sa_std.zig（避免大爆炸改动）
