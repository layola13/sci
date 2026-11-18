# DCE 机制为什么没能解决 sa_std 过大（实测）

日期：2026-11-18
分支：wasm

## 一、直接结论

**DCE 存在且生效，但被 `pub export fn` 压制在编译期；链接期的 section GC 虽然生效，却发生在解析之后，救不了 link 时间。**

## 二、决定性实验（2000 函数，wasm object）

| 编译方式 | object 大小 | 函数数 |
|---|---:|---:|
| 2000 个全 `pub export fn` | 242,829 B | **2000**（全部保留） |
| 2000 个 `pub fn` + 1 个 export | 1,882 B | **2**（DCE 掉 1998 个） |

**Zig 编译器对 `pub export fn` 不做 DCE**——export 语义把它们视为必须保留的入口点。这是 sa_std 的根本问题：1298 个 `pub export fn` + comptime 强制引用块把它们全部 emit。

## 三、sa_std 实测数据

- `sa_std_zcu.o`：8009 函数，14.1MB（构建 strip 后 7.3MB）
  - 1298 个 `pub export fn`（源码声明）
  - ~6700 个内部函数（泛型实例化、辅助函数，被 export 函数传递性引用）
- 最终 wasm：只 export 2 符号（memory + _start），只保留 16 函数，1.6KB code

## 四、两层 DCE 的不同命运

| 层级 | 机制 | 是否生效 | 效果 |
|---|---|---|---|
| 编译期（Zig） | DCE on `pub fn` | ✅ 生效 | 非 export 的未用函数被删（B 实验 2000→2） |
| 编译期（Zig） | DCE on `pub export fn` | ❌ 被压制 | export 函数全部保留（A 实验 2000→2000） |
| 链接期（wasm-ld） | section GC / `--gc-sections` | ✅ 生效 | 最终产物 8009→16 函数，1.6KB |
| 链接期（wasm-ld） | 符号表+reloc 解析 | — | **28ms，发生在 GC 之前，无法省** |

**关键点**：链接期 GC 虽然把产物裁到 16 函数，但它必须先**全量解析 7.3MB object 的符号表和 reloc**（28ms）。DCE 省的是产物大小和运行时，不省解析时间。

## 五、已做手段 vs 根因

| 手段 | 性质 | 效果 |
|---|---|---|
| 构建时 `.strip=true`（wasi） | 治标 | archive 14.1→7.3MB（去 DWARF） |
| 链接时 `--strip-debug` | 治标 | 产物 5.5MB→1.8KB |
| 拆 object | 治标（缓解解析） | 实测省 12-28ms，未落地 |
| **改 `pub export fn` 为按需导出** | **根治** | **未做——需改 ABI 机制** |

JEV 裁定：根因 h1（export 压制 DCE）置信度 94%，当前修复是 symptom_patch 88%。

## 六、为什么不能简单把 `pub export fn` 改成 `pub fn`

这些 export 符号是 SA ABI 契约——`.sai` 里的 `@extern fn sa_sha256(...)` 按符号名在链接时解析。改成 `pub fn` 会被 DCE 删掉，导致链接时 undefined symbol。根治需要：
- 扫描所有 `.sai` 契约，收集真正被引用的 export 符号清单
- 只 export 这些符号，其余改 `pub fn` 让 DCE 生效
- 但这是 ABI 级改动，风险高，且列表需随契约维护

## 七、一句话

**DCE 没坏，是被 `pub export fn` 关掉了。编译期 export 强制全保留（2000→2000），链接期 GC 虽把产物裁到 16 函数但解析 7.3MB 符号表的 28ms 已经花掉。已做的 strip 都是治标；根治要改 export 机制（按 .sai 契约按需导出），属 ABI 级改动，尚未做。**
