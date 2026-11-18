# 按模块拆 object 实验：失败（已回滚）

日期：2026-11-18
分支：wasm

## 一、结论

**按源文件拆 sa_std 为独立 object 在 Zig 模块系统下不可行，已回滚。**

JEV 裁定：根因 h1（每个编译单元重复内联依赖闭包）置信度 96%。

## 二、实验实现（已回滚）

1. `sa_std.zig`：把 toml/yaml 的 comptime 引用块（525-584 行）包在 `if (!is_wasm)` 里
2. `build.zig`：wasi target 下用 `b.addObject` 编译 sa_toml.zig / sa_yaml.zig 为独立 object，`addObjectFile` 进 archive

## 三、实测数据（决定性）

| 指标 | 改前 | 改后 |
|---|---:|---:|
| 主 object 函数数 | 8009 | 7460（减 549） |
| sa_toml 独立 object | — | 870 函数（源码仅 54！） |
| sa_yaml 独立 object | — | 1026 函数 |
| archive 大小 | 7.33 MB | **8.27 MB（净增）** |
| link 时间 | 80 ms | **89 ms（未改善）** |

## 四、失败根因

**Zig 每个独立编译单元都会重复内联共享依赖闭包（sio / std.Io / Mutex）**：
- sa_toml.zig 源码 54 个顶层函数，独立 object 却有 870 个函数——多出 816 个全是 sio/Io 依赖副本
- sa_yaml 同理，1026 个函数

主 object 减了 549 个函数，但两个独立 object 净增 1896 个函数（大量重复的依赖代码）。archive 变大，wasm-ld 要解析的总符号表反而更多，link 未提速。

这与 C 的 `.o` 模型不同：C 的 .o 只包含本文件的代码，符号是 External 的；Zig 的模块系统是源码级内联，每个 CU 自带依赖闭包。

## 五、为什么之前"A 方案可行性"的代理实验会误导

之前用 `zig build-obj` 手工生成的 gen100/gen8000 是**自包含的人造 Zig 源码**（只依赖 extern host，无 sio/std.Io 共享闭包），所以拆开后没有重复依赖，按需 pull 省 12ms。真实 sa_std satellite 带完整依赖闭包，情况完全不同。

## 六、最终结论

wasm link 优化的可用手段已穷尽：
- ✅ 构建时 strip（14→7.3MB）—— 已交付
- ✅ 链接时 --strip-debug（5.5MB→1.8KB）—— 已交付
- ❌ 拆 object —— 实验失败（Zig 依赖闭包重复），已回滚
- ❌ 绕开 zig cc —— 破坏 WASI 入口，已否
- ❌ 按需 export —— 契约要求 1250 符号，数据否决

剩余 ~80ms link 是 Zig 编译模型 + WASI ABI + 静态链接的结构性成本。对标 MoonBit 18ms 的 5× 差距无法通过小改动消除。

**建议停止 wasm link 优化，转向其他更高 ROI 的方向（如预编译接口缓存解决前端契约加载）。**

## 七、状态

改动已全部回滚，archive 恢复 7.33MB，工作区 clean。autocommit 守护仍在运行。
