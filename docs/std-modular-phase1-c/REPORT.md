# SA 标准库模块化 Phase 1 — 领域 C（collections + string + text + encoding）报告

- **任务**：Phase 1 只做 Std 目录与模块边界整理，不修 bug、不跑测试。发现缺陷只记录、不修复。
- **执行日期**：2026-11-22
- **盒子**：新 Colab 盒 bd4991109185（SSH `root@31.58.87.230:25024`）
- **工作仓**：盒上 `/content/kit-work/sci2-agentS1C`（sci2 副本，分支 `sa-optimize`，HEAD `be42fa97`）
- **合规**：只动该副本，未动 `/content/kit-work/sci2` 主树与 `/content/sa_all/sci` 原仓；**未 commit、未 push、未合并 main**；未跑任何构建与测试（无 `zig build`、无测试套件）；未修复任何 bug；未动 `tests/`；未动 `src/`（Zig 宿主）；未动其他域的文件（除根 `prelude.sa`/`prelude.sal` 中属于本域的导入行，见 §7）；未动 `num.sa`。
- **工作树状态**：35 个重命名（`git mv`，已 staged，未 commit）+ 6 个删除 + 4 个修改 + 35 个新增 shim（untracked）+ 本报告目录 `docs/std-modular-phase1-c/`（untracked）。

## 1. 结论总览

| 项目 | 数量 |
|---|---|
| 移动的文件（`git mv`） | 35 |
| 删除的文件（已无用的 collections/ 旧 shim） | 6 |
| 新增旧路径薄 shim | 35 |
| 域内文件总数（移动后） | collections 24、string 15、text 6、encoding 12、alloc 8（含 1 个 shim） |
| sa_std 源码文件总数 | 363 → 392（+35 shim −6 删除） |
| 更新的域内 `@import` | 全部已更新为规范路径（见 MAPPING.md） |
| 静态 `@import` 解析检查 | **PASS：825 处引用，0 悬空**（见 IMPORT-CHECK.md） |
| 修复的 bug | 0（按禁令） |
| 需要的 Zig 宿主改动 | 0（见 §2.4） |
| Breaking change | 1 处（见 §5：6 条 `collections/<name>.sa` 旧 shim 路径消失，仓内 0 引用） |

## 2. Re-export 机制判定：支持，用 1 行 `@import` 薄 shim（已有先例）

SA 没有 `pub use` 式的符号级 re-export。既有机制是：**一个只含 1 行 `@import` 的文件就是转发 shim**。本域内已有先例：

- `sa_std/collections/hashmap.sa` 等 6 个文件在移动前就是 1 行 `@import "../hashmap.sa"` 的 shim；
- `.sal` 同样如此：`sa_std/ascii.sal` = `@import "core/ascii.sal"`，`sa_std/collections/prelude.sal` = `@import "../collections.sal"`。

宿主侧语义已核对源码（只读，未改动）：

- 解析：`@import "sa_std/..."` 按 `SA_STD_DIR`/仓库 `sa_std` 根解析；其他路径按导入文件所在目录相对解析（`src/pkg/resolver.zig` `resolveStandardImport`/`resolveImport`；`src/flattener/injectimportedfile.zig` 以 `dirname(source_path)` 为 `base_dir`）。
- 去重：同一规范路径只展开一次（`src/flattener/expandimportsinto.zig` 的 `seen_paths`；`injectimportedfile.zig` 的 `seen_paths` 检查）。根 prelude 同时直引 `hashmap.sa` 与经 `collections/prelude.sa` 的同一文件，是今天就已存在的用法。
- 同胞自动注入：导入某 `.sa` 文件时，flattener 会自动注入同目录同 stem 的 `.sai`（extern 声明）与 `.sal`（布局常量）（`injectimportedfile.zig` `injectImportedFile` 尾部）。**因此 `.sa` 与同 stem 的 `.sai`/`.sal` 必须同目录移动**，否则自动注入失效。本次 35 个移动全部遵守此规则（见 §4 与 IMPORT-CHECK.md 的 sibling-parity 检查，0 问题）。
- 递归展开与扩展名无关：`expandImportsInto` 对任何被导入文件的 `@import` 行都递归展开（`.sal` 文件满是 `@import` 就是证据）。因此 `.sai` shim 同样可用——虽然仓内此前没有任何 `.sai` 文件含 `@import`（grep 为 0），但机制上与 `.sal` shim 同路；本次 `.sai` shim 共 3 个（`string.sai`、`growvec.sai`、`ts_unicode.sai`），其目标均经静态检查确认存在。** caveat：因禁令未跑构建，shim 的实际编译行为未经构建验证，Phase 2 首轮构建需重点验证这 3 个 `.sai` shim 与 3 个 `.sla` shim。**
- `.sla` shim：`.sla` 文件的 `@import` 用 `sa_std/` 前缀形式（SLA 工具链惯例，如 `vec_grow.sla` 原样），本次 3 个 `.sla` shim 均用 `sa_std/` 前缀。

### 2.1 兼容策略

旧路径全部留薄 shim（2 行：1 行注释 + 1 行 `@import`），转发到规范路径。仓内 293 个 `tests/` 文件与 6 个 `demos/` 文件引用本域旧路径（`sa_std/` 前缀形式），按禁令未动，全部经由 shim 继续解析。域外 `sa_std/` 文件引用本域旧路径的（如 `ffi.sa` 引 `string.sa`、`array.sa` 引 `vec.sa`、`rust_core.sa` 引 `collections/linked_list.sa`、`core/iter.sa` 引 `../vec_runtime_macros.sa`），按“不动其他域的文件”禁令未改，同样经由 shim 继续解析；其规范路径更新留给各域 owner（见 §8）。

### 2.2 目标结构对照（用户提案第 1 节）

| 提案 | 落实 |
|---|---|
| `collections/` 下分 `vec/`、`hashmap/`、`hashset/`、`deque/`、`heap/` | 已落实；另增 `btree/`（BTreeMap+Set 同族）、`growvec/`、`linked_list.sa` 平铺（见下） |
| `string/` 下分 `string/`、`builder/`、`utf8/`、`encoding/` | `string/`、`builder/`、`utf8/` 已落实；`encoding/` 预留为空目录未建（git 不跟踪空目录；UTF-8/UTF-16 编解码仍在 `string.sa` 内，拆分是 Phase 2+ 的事，见 DEF-16） |
| `text` 与 `encoding` 保持独立域 | 已落实，两域零文件移动（仅 `encoding/bitpack.sla` 更新了 1 行 vec 导入） |

两处对提案的偏离（均已记录在案）：

1. **`linked_list` 未建子目录**：`collections/linked_list.sa` 若移入 `collections/linked_list/linked_list.sa`，旧路径 `collections/linked_list.sa` 会被同名目录占用、无法留 shim，而域外文件 `rust_core.sa:26-27` 正引用该路径且我不能改它。故 `linked_list.sa`/`.sal` 保持平铺在 `collections/`，只更新其内部 1 行导入（`../vec.sa` → `vec/vec.sa`）。
2. **`alloc/` 运行时层保留不动**：`alloc/vec.sa`（969 行，`sa_vec_*` 运行时）与 `alloc/growvec.sa`（307 行，运行时）未移入 `collections/vec/`。理由：它们是 `collections` 与 `string` 共用的分配运行时（`string.sal` 引 `alloc/vec.sal`，`collections.sal` 引 `alloc/layout.sal`）；移入 `collections/` 会让 `string → collections` 出现跨域边，比现在 `collections/string → alloc` 更糟。`alloc/` 现只剩运行时 + `layout.sal` + prelude，归属问题（并入 core 还是保留）留给 Phase 2（见 DEF-15）。

## 3. 重复文件判定

| 旧路径 A | 路径 B | 判定 |
|---|---|---|
| `vec.sa`（5784 行，759 个 `VEC_*` 宏） | `alloc/vec.sa`（969 行，22 个 `@export sa_vec_*`） | **不是重复，是分层**：顶层是宏 facade，调 `alloc/` 的运行时；`vec.sa:1-2` 显式导入 `alloc/vec.sa`。规范版 = 两者各司其职，facade 入 `collections/vec/`，运行时留 `alloc/`。 |
| `string.sa`（12241 行） | `alloc/string.sa`（3 行） | **不是重复**：后者只含 `STR_FROM_CONST` 一个宏。已改名移入 `string/builder/str_from_const.sa`，旧路径留 shim。 |
| `hashmap.sa`（2736 行） | `collections/hashmap.sa`（1 行） | **后者是前者的转发 shim**（`@import "../hashmap.sa"`），非重复实现。规范版 = 顶层实现，移入 `collections/hashmap/`，旧 shim 删除。 |
| `hashset.sa` / `btree_map.sa` / `btree_set.sa` / `binary_heap.sa` / `vec_deque.sa` | `collections/` 下同名 1 行文件 | **同上，全部是转发 shim**。规范版 = 顶层实现，分别移入 `collections/hashset/`、`collections/btree/`、`collections/heap/`、`collections/deque/`，旧 shim 删除。 |
| `growvec.sa`（325 行，`GROWVEC_*` 宏） | `alloc/growvec.sa`（307 行，运行时） | **不是重复，是分层**：顶层 facade（`@import "alloc/growvec.sa"`）+ `alloc/` 运行时。facade 入 `collections/growvec/`，运行时留 `alloc/`。 |
| `hash.sa`（1486 行，`BUILD_HASHER_DEFAULT_*` 宏） | `core/hash.sa`（小 facade，`@import "../hashmap.sa"`） | **同名不同物**：前者是哈希器实现，后者是 core 内包在 hashmap 上的 facade。两者均未移动（`hash.sa` 是共享原语，归属待定；见 DEF-09）。 |
| `ascii.sa`（2 行） | `core/ascii.sa`（784 行） | **前者是后者的转发 shim**。规范版 = `core/ascii.sa`，shim 移入 `string/utf8/ascii.sa`，顶层留 shim。 |
| `vec.sal`（1 行，`Vec_data = +0`） | `alloc/vec.sal`（3 行，`Vec_SIZE/ptr/cap/len`） | **不是重复，是互补**：两份布局常量内容不同。各自随所属 `.sa` 移动，未合并（见 DEF-10）。 |

另：`string.sa` 与 `num.sa` 无重复关系；`num.sa` 不在本域，未动。

## 4. 新目录结构

```
sa_std/
  collections/
    prelude.sa            # 聚合 7 个公开模块（新路径）
    prelude.sal           # -> collections.sal
    collections.sal       # TryReserveError（由顶层移入）
    vec/                  # Vec facade + SLA 辅助
      vec.sa vec.sal vec_grow.sla vec_packed.sla vec_runtime_macros.sa
    hashmap/  hashmap.sa hashmap.sal
    hashset/  hashset.sa hashset.sal
    btree/    btree_map.sa btree_map.sal btree_set.sa btree_set.sal
    heap/     binary_heap.sa binary_heap.sal
    deque/    vec_deque.sa vec_deque.sal
    growvec/  growvec.sa growvec.sai        # facade；运行时仍在 alloc/
    linked_list.sa linked_list.sal          # 平铺（见 §2.2 第 1 条）
  string/
    string/   string.sa string.sal string.sai cstring.sa cstring.sal
    builder/  string_format.sa str_from_const.sa（原 alloc/string.sa 改名）
    utf8/     char.sa char.sal ascii.sa ascii.sal
    ts/       ts_string.sa ts_unicode.sa ts_unicode.sai
    str.sla
    # encoding/ 预留，未建目录
  text/       # 未移动
    prelude.sa prelude.sal regex.sa regex.sai regex.sal regex.sla
  encoding/   # 未移动
    prelude.sa prelude.sal json.sa json.sai json.sal json.sla
    base64.sai bitpack.sla toml.sai toml.sla yaml.sai yaml.sla
  alloc/      # 运行时层，保留
    vec.sa vec.sal growvec.sa growvec.sal layout.sal prelude.sa prelude.sal
    string.sa                 # shim -> ../string/builder/str_from_const.sa
```

顶层旧路径（`vec.sa`、`string.sa`、`hashmap.sa` 等 35 个）全部保留为 2 行薄 shim。完整旧→新对照见 MAPPING.md。

## 5. Breaking change：1 处

6 条 `collections/<name>.sa` 旧 shim 路径被删除（`hashmap`、`hashset`、`btree_map`、`btree_set`、`binary_heap`、`vec_deque`），因为同名位置现为目录，无法再放 shim 文件。仓内 grep 确认 0 引用（`check_imports.py` 第 3 节）；但仓外若有人直接 `@import "collections/hashmap.sa"`，会断。其他所有旧路径均有 shim，**不是** breaking change。删除的只是 1 行转发文件，内容已移入 `collections/<family>/<name>.sa`。

## 6. 依赖方向实测（与“只依赖 core”的目标对照）

目标“collections 与 string 只依赖 core，不依赖 io/net/db/http”**在字面上不成立**，实测依赖如下（完整清单见各域 MANIFEST）：

| 依赖边 | 证据 | 定性 |
|---|---|---|
| collections → `core/*`（slice、mem、iter） | 各文件头 `@import` | 符合目标 |
| collections → `alloc/*`（vec/growvec 运行时、layout） | `hashmap.sa:3-4`、`vec.sa:1-2`、`collections.sal:1` | 运行时层依赖，建议承认为允许方向（alloc 是共享运行时） |
| collections → `num.sa` | `hashmap.sa:6`、`hashset.sa:6`、`btree_map.sa:5`、`binary_heap.sa:8`、`vec_deque.sa:8`、`alloc/vec.sa:27`、`alloc/growvec.sa:3` | 边界偏差（DEF-03）：num 是数值原语，事实上的 core 邻层 |
| collections → `hash.sa`（顶层） | `vec.sa:8`、`btree_map.sa:7`、`vec_deque.sa:10` | 哈希原语，归属待定（DEF-09） |
| string → `core/*` + `collections/vec` | `string.sa:1-6` | 符合目标（vec 是底层容器） |
| string → `hash.sa`、`fmt.sai` | `string.sa:8-9` | 偏差（DEF-02）；`fmt.sai` 只是 extern 声明头，无代码依赖 |
| string → `ffi.*` | `string.sal:2`（`ffi.sal`）、`cstring.sa:2-3`（`ffi.sa` 实代码） | 偏差（DEF-11/12）；CString 本质上需要 FFI |
| string/ts → `ts_array.sa` | `ts_string.sa:15` | 域外 ts_* 簇依赖（DEF-13） |
| encoding → `collections/vec` | `bitpack.sla:104`（已更新为规范路径） | 偏差（DEF-05） |
| text →（仅 `core/slice.sal`，经 `text/prelude.sal`） | — | 符合目标；regex 实现在 Zig 侧（DEF-07） |
| 反向：`core/hash.sa` → collections（`../hashmap.sa`） | `core/hash.sa:1-2` | 分层倒置（DEF-01），core 域的问题，登记在案未动 |
| 反向：`core/iter.sa` → `vec_runtime_macros.sa` | `core/iter.sa:4` | core→collections 边，现经 shim（DEF-04） |

结论：建议把允许方向正式定为 **core + alloc（运行时）+ num（数值原语）+ 各 `.sai` extern 声明头**，io/net/db/http 仍禁入；`hash.sa` 与 `string → ffi` 两处需 Phase 2 定归属。

## 7. 改动的文件清单（除移动与 shim 外）

- `sa_std/collections/prelude.sa`：7 行导入改为新子路径（成员不变；growvec 未加入聚合，见 DEF-17）。
- `sa_std/collections/prelude.sal`：`../collections.sal` → `collections.sal`。
- `sa_std/collections/linked_list.sa`：`../vec.sa` → `vec/vec.sa`（其余不动）。
- `sa_std/encoding/bitpack.sla`：`sa_std/vec.sa` → `sa_std/collections/vec/vec.sa`。
- `sa_std/prelude.sa` / `sa_std/prelude.sal`：**仅本域的 12 行导入**改为规范路径（其余行原样；其他域的导入行未动）。
- 其余 35 个移动文件的内部 `@import` 全部更新为规范相对路径（逐文件核对见 MAPPING.md）。

未动：`tests/`（含 293 个引用本域旧路径的文件）、`demos/`、`src/`、其他域的 `sa_std/` 文件、`num.sa`、`hash.sa`、`ptr.sa`、`fmt.*`、`io.*`、`ffi.*`（除被移动的 `cstring` 外）、`core/*`。

## 8. 需要其他域 / 宿主侧确认的事（未做，留待 Phase 2）

1. 域外文件引用本域旧路径的规范化（均经 shim 正常工作，不急）：`ffi.sa`（`string.sa`、`string.sai`）、`ffi/prelude.sa`（`cstring.sa`）、`array.sa`（`vec.sa`、`hash.sa`）、`path.sa`（`string.sa`）、`io.sa`（`string.sai`）、`core/prelude.sa`（`ascii.sa`）、`core/hash.sa`（`../hashmap.sa`、`.sal`）、`core/iter.sa`（`../vec_runtime_macros.sa`）、`rust_core.sa`（`collections/linked_list.sa`、`.sal`）、`url.sla`/`ip.sla`/`http_proxy.sla`（`string_format.sa`）、`ts_object.sa`/`ts_jsval.sa`（`ts_string.sa`）。
2. `hash.sa`（1486 行实现）的归属：`core/hash/` 还是 `collections/hash/`；`core/hash.sa` 同名 facade 的去留（DEF-09）。
3. `string/encoding/` 子目录的填充：从 12241 行的 `string.sa` 中抽 UTF-8/UTF-16 编解码，是拆文件工作，明确不属于 Phase 1（DEF-08/16）。
4. `string.sa` 12241 行大文件的拆分方案（Phase 2+）。
5. `encoding/prelude.sa` 只聚合 `json.sa`，`prelude.sal` 为空文件（DEF-06）。
6. Zig 宿主侧：本次**无需**改动（`src/`、`tools/`、`build.zig*` 均无硬编码的 std 文件清单；`sa_std/sa.mod` 只有 `package "sa_std"` 一行声明）。但 Phase 2 首轮构建必须验证 3 个 `.sai` shim 与 3 个 `.sla` shim（见 §2）。
7. 新近用户定调（2026-11-22 MEMORY.md 更新）：“先用 Zig 做标准库模块化与按需加载”“导入同时支持符号级与模块级，底层统一为符号依赖图”——符号级导入是 Phase 2+ 方向，本次只做了模块级路径整理，未引入符号级机制。

## 9. 缺陷清单

共 21 项，全部**只记录、未修复**，见 DEFECTS.md（含文件、行号、描述、严重度）。其中结构性问题为主，未发现已证实的运行时 bug（未跑测试，无法证实或证伪运行时行为）。

## 10. 数字附录

- 移动前 `sa_std/` 源码文件 363 个（`.sa/.sai/.sal/.sla`），顶层平铺 217 个。
- 域内最大文件：`string/string/string.sa` 12241 行；`collections/vec/vec.sa` 5784 行（759 个宏）；`collections/deque/vec_deque.sa` 4925 行。
- 域内 `.sa/.sai/.sal/.sla` 行数合计（移动后清单）：40688 行（见 MAPPING.md 的 `wc -l` 表）。
- 仓内以 `sa_std/` 前缀引用本域旧路径的文件数：`vec.sa` 109、`string.sa` 74、`vec_deque.sa` 21、`string_format.sa` 4、`ts_string.sa` 3、`char.sa`/`ascii.sa` 各 2、`string.sai` 2、`growvec.sa` 1（其余为 0）。全部经 shim 解析。
