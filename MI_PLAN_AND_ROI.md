# 抄 MoonBit .mi：方案与 ROI 评估（实测）

日期：2026-11-18

## 一、MoonBit .mi 的本质

`.mi` = 把**依赖模块的类型检查成果**（类型、trait、method、extern 签名）持久化成二进制接口文件。下游加载 `.mi` 后免于重新解析+类型检查依赖源码。核心价值：**增量**——依赖没变就加载缓存，只重编改了的模块。

## 二、SA 生态的对应点（实测定位）

预言机在 **sa_plugin_sla** 仓（不是 sci，也不是 sci-wasm 分支）：
- `type_checker.zig:6476 loadContracts()` 每次重新 `parseSai`/`parseSal` 文本 → 注册符号表
- `plugin_import_expand.zig` 递归加载 30 个契约文件
- profile 实测：`load contracts summary: roots=3 visited=30`

### 已有缓存（关键发现，别重复造轮子）
- `plugin_freshness.zig`：整编译 all-or-nothing 缓存（零变更直接返回产物；改一行→全量重跑）
- `plugin_import_expand.zig:38`：`.sla-cache/imports/*.lst` **磁盘持久化**的 @import 路径列表缓存（跳过文本行扫描）
- `import_type_scan_cache`：进程内类型扫描缓存（跨模块复用，不跨进程）

### 实测契约加载耗时（连续 5 次 sla check）
```
run1: 27ms  run2: 32ms  run3: 10ms  run4: 10ms  run5: 25ms
```
冷态 27-93ms（含早期 93ms 观测），**热态可到 10ms**（imports 缓存命中，16 个 .lst 文件已生成）。

## 三、ROI 分析

| 维度 | 评估 |
|---|---|
| 收益 | 冷态省 17-83ms/次；但热态已 10ms，日常增量收益有限 |
| 真正瓶颈 | `.mi` 要缓存的"类型信息"parse 本身不是最大头；25ms 的 `string.sa scan` 是 import 图扫描，已有 .lst 缓存覆盖 |
| 与现有缓存重叠 | imports 路径缓存 + freshness 门已覆盖大部分；.mi 增量的是"类型信息持久化"，边际收益不明确 |
| 工程量 | 中型：需设计 `.mi` 二进制格式（extern 签名、layout、宏元数据）、序列化/反序列化、缓存失效（内容哈希）、接入 loadContracts |
| 风险 | **高**：在 sa_plugin_sla 仓，其他线程正在改（有未提交改动 `demos/rosetta/123_barrier_sync/main.sa`），需先复制隔离副本 |
| 契约规模 | 1259 个 extern 符号——即便 .mi 缓存了，加载 1259 个签名到符号表本身也有成本 |

## 四、真正的痛点可能不是 parse

`.mi` 解决的是"重复 parse 类型信息"。但实测显示：
- 热态 10ms：现有缓存已把重复 parse 压到很低
- 波动（10-32ms）：更像机器负载 + 缓存命中不稳定，而非 parse 本身

**MoonBit 有 `.mi` 是因为它没有 SA 这种 freshness 门 + imports 缓存的组合**。SA 已有类似机制，只是覆盖率/稳定性不如 .mi。

## 五、建议方案（如果要做）

1. **隔离副本**：先复制 sa_plugin_sla → sa_plugin_sla-mi（含 .git），避免覆盖其他线程改动
2. **先量化 parse 占比**：在 loadContracts 里加细粒度计时（parseSai/parseSal vs 符号表注册 vs source_expand），确认 .mi 缓存哪一段
3. **设计 .mi 格式**：
   - 内容：extern 签名（名字+参数类型+cap）、layout 定义、宏元数据
   - key：契约文件内容哈希（仿 cache_version + Wyhash）
   - 存储：`.sla-cache/mi/<stem>-<hash>.mi`
   - 失效：内容哈希变化自动失效
4. **接入**：loadContracts 先查 .mi，命中则反序列化注册；miss 则 parse + 写 .mi
5. **验证**：冷/热两轮对比，确认收益 > 工程量

## 六、决策要点（需用户确认）

- **在哪做**：sa_plugin_sla（真实收益）还是 sci-wasm（原型验证，与真实代码脱节）？前者需隔离副本。
- **是否值得**：热态已 10ms，冷态 .mi 收益 17-83ms，但工程量中型、风险高。
- **替代**：如果只是想体验"预编译接口缓存"思路，也可以在一个最小 demo 上做原型（不接真实工具链），成本极低。

## 七、结论

MoonBit `.mi` 的思路是对的，但 SA 生态**已有 freshness 门 + imports 列表缓存**覆盖了大部分场景，热态 load contracts 已降到 10ms。真正的边际收益在"类型信息持久化"，需先量化 parse 占比再决定。建议先做隔离副本 + 细粒度计时，确认 ROI 后再实现 .mi 格式。
