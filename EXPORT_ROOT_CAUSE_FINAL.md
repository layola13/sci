# export 根因最终裁定（Haxe 类比 + 方向2 可行性）

日期：2026-11-18
分支：wasm

## 一、Haxe 类比：用户是对的，我之前的措辞错了

Zig 三层可见性 DCE 实验（2000 函数）：

| 写法 | 未使用时 | 对应 Haxe |
|---|---|---|
| 私有 `fn` | DCE 掉 | private 方法 |
| 纯 `pub fn` | **DCE 掉** | **pub 方法（一样删）** |
| `pub export fn` | **强制保留** | （Haxe 无对应物） |

- 用户说"Haxe 的 pub 方法没用也删，为什么 Zig 无效"——**成立**。
- Zig 的纯 `pub fn` 和 Haxe 的 pub 方法**行为一致**，都会 DCE。
- sa_std 的问题不是 `pub`，而是 multi 关键字 **`pub export`** 里的 `export`——这是链接器符号导出声明，不是可见性修饰符。
- 编译模型差异：Haxe 全程序编译（看到所有入口，pub 敢删）；Zig 逐编译单元（export 是对外 ABI 承诺，必须保留）。

## 二、方向2（按需 export）可行性：❌ 不可行

决定性的契约符号统计：

| 指标 | 数量 |
|---|---:|
| `.sai` 契约声明的 extern 符号 | 1259 |
| `pub export fn` 符号 | 1316 |
| **交集** | **1250** |
| 契约有但无 export | 9 |
| export 有但契约无 | 66 |

**1250/1259 的契约符号都需要 export 位**。也就是说：
- sa_std 的 export 符号几乎全是 SA ABI 契约强制要求的，DCE 根本不能删（删了 `.sai` 的 `@extern` 就 undefined）
- "扫描契约生成 export 清单"和现有 1298 个几乎一样，无优化空间
- 唯一可 DCE 的是那 66 个 export 但契约无的（dlopen/dlsym/sa_deno_* 等），占比 5%，收益微小

**结论：方向2（按需 export）被数据否决。** 这不是"风险高"，而是"契约本来就要求这么多符号，无从削减"。

## 三、`comptime { _ = &func }` 的真相

实验 A：comptime 强制引用对纯 `pub fn` **不阻止 DCE**（两个测试函数都被删）。所以它从来不是"防止 DCE 的手段"——真正防止 DCE 的是 `export` 关键字。sa_std.zig 里那 300 行 comptime 块只是代码作者当时为了确保 export 生成而写的，实际上 export 本身就够了。

## 四、最终根因链条（完整、精确）

```
SA ABI 契约（.sai，1259 个 @extern）
    ↓ 必须提供符号
1298 个 pub export fn（Zig 强制 emit，DCE 不能碰）
    ↓ 加上 ~6700 内部函数（被 export 传递引用）
单 compilation unit → 8009 函数 / 7.3MB object
    ↓ wasm-ld 链接时
必须全量解析符号表 + reloc（28ms）
    ↓ GC 后
最终 wasm 只保留 16 函数 / 1.6KB
```

**根因 = 契约规模（1259 个符号必须暴露）+ 单 compilation unit**。不是 DCE 失效，也不是 pub 的问题。

## 五、唯一有效的攻击面（修正后）

既然 1250 个 export 符号必须保留，那唯一能省的只有"解析单 object 的 28ms"，方法仍是：
- **拆 object（多 compilation unit）**：让 export 符号分散到多个 object，wasm-ld 通过 archive 符号索引只 pull 被引用的 object。已实测可省 12-28ms。
- 这不改变 export 符号数量（ABI 不变），只改变它们的物理布局。

## 六、给定的三个方向里哪个对

- 方向2（按需 export）：❌ 被契约数据否决
- 拆 object：✅ 唯一可行的 28ms 攻击面，但工程量大
- 已交付的 strip：治标，已省最大头的体积和 link

## 七、诚实结论

用户追问 DCE 帮帮我找到了真正的根因——不是 DCE 坏了，而是 SA ABI 契约本身就要求 1250 个符号暴露，DCE 无从下手。方向2数据上不可行。剩下唯一能优化的是拆 object 的 12-28ms，但那需要改 28 个卫星 + build.zig，ROI 有限。已交付的 strip 优化（link 204→80ms）是这一轮最大的实际收益。
