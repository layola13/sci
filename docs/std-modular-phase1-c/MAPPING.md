# 模块映射表（旧路径 → 新路径）— 领域 C

工作仓：`/content/kit-work/sci2-agentS1C`，分支 `sa-optimize`，HEAD `be42fa97`。行数为 `wc -l` 实测（无尾换行的单行文件计为 0，如 `alloc/prelude.sa` 实为 1 行）。

图例：`MV` = `git mv`（已 staged，未 commit）；`SHIM` = 旧路径留 2 行薄 shim（注释 + 1 行 `@import`）；`DEL` = 删除（旧文件本身就是 1 行 shim）；`MOD` = 内容修改（仅 `@import` 行）。

## 1. collections 域（22 个移动 + 6 个删除）

| 旧路径 | 新路径 | 行数 | 状态 | 备注 |
|---|---|---|---|---|
| `sa_std/vec.sa` | `sa_std/collections/vec/vec.sa` | 5784 | MV + SHIM | 759 个 `VEC_*` 宏；内部 8 行导入改为 `../../` |
| `sa_std/vec.sal` | `sa_std/collections/vec/vec.sal` | 1 | MV + SHIM | 仅 `#def Vec_data = +0`；与 `alloc/vec.sal` 互补，未合并 |
| `sa_std/vec_grow.sla` | `sa_std/collections/vec/vec_grow.sla` | 86 | MV + SHIM | 2 行 `sa_std/` 导入更新；shim 用 `sa_std/` 前缀 |
| `sa_std/vec_packed.sla` | `sa_std/collections/vec/vec_packed.sla` | 282 | MV + SHIM | 1 行 `sa_std/` 导入更新；shim 用 `sa_std/` 前缀 |
| `sa_std/vec_runtime_macros.sa` | `sa_std/collections/vec/vec_runtime_macros.sa` | 11 | MV + SHIM | 无导入；`core/iter.sa:4` 经 shim 引用 |
| `sa_std/hashmap.sa` | `sa_std/collections/hashmap/hashmap.sa` | 2736 | MV + SHIM | 6 行导入更新（`vec.sa`→`../../collections/vec/vec.sa` 等） |
| `sa_std/hashmap.sal` | `sa_std/collections/hashmap/hashmap.sal` | 20 | MV + SHIM | 无导入 |
| `sa_std/hashset.sa` | `sa_std/collections/hashset/hashset.sa` | 1059 | MV + SHIM | 5 行导入更新（`hashmap.sa`→`../hashmap/hashmap.sa` 等） |
| `sa_std/hashset.sal` | `sa_std/collections/hashset/hashset.sal` | 18 | MV + SHIM | 无导入 |
| `sa_std/btree_map.sa` | `sa_std/collections/btree/btree_map.sa` | 2320 | MV + SHIM | 5 行导入更新；与 `btree_set` 同入 `btree/` |
| `sa_std/btree_map.sal` | `sa_std/collections/btree/btree_map.sal` | 11 | MV + SHIM | 无导入 |
| `sa_std/btree_set.sa` | `sa_std/collections/btree/btree_set.sa` | 1072 | MV + SHIM | 导入不变（`btree_map.sa` 同目录） |
| `sa_std/btree_set.sal` | `sa_std/collections/btree/btree_set.sal` | 6 | MV + SHIM | 无导入 |
| `sa_std/binary_heap.sa` | `sa_std/collections/heap/binary_heap.sa` | 3004 | MV + SHIM | 7 行导入更新 |
| `sa_std/binary_heap.sal` | `sa_std/collections/heap/binary_heap.sal` | 7 | MV + SHIM | 无导入 |
| `sa_std/vec_deque.sa` | `sa_std/collections/deque/vec_deque.sa` | 4925 | MV + SHIM | 7 行导入更新 |
| `sa_std/vec_deque.sal` | `sa_std/collections/deque/vec_deque.sal` | 8 | MV + SHIM | 无导入 |
| `sa_std/growvec.sa` | `sa_std/collections/growvec/growvec.sa` | 325 | MV + SHIM | facade；4 行导入更新；运行时留 `alloc/` |
| `sa_std/growvec.sai` | `sa_std/collections/growvec/growvec.sai` | 15 | MV + SHIM | 无导入；随 facade 同目录移动（同胞自动注入，见 REPORT §2） |
| `sa_std/collections.sal` | `sa_std/collections/collections.sal` | 13 | MV + SHIM | 1 行导入更新（`alloc/layout.sal`→`../alloc/layout.sal`） |
| `sa_std/collections/hashmap.sa` | —（删除） | 1 | DEL | 本身就是 shim；新位置为目录，同名文件无法保留；仓内 0 引用 |
| `sa_std/collections/hashset.sa` | —（删除） | 1 | DEL | 同上 |
| `sa_std/collections/btree_map.sa` | —（删除） | 1 | DEL | 同上 |
| `sa_std/collections/btree_set.sa` | —（删除） | 1 | DEL | 同上 |
| `sa_std/collections/binary_heap.sa` | —（删除） | 1 | DEL | 同上 |
| `sa_std/collections/vec_deque.sa` | —（删除） | 1 | DEL | 同上 |
| `sa_std/collections/linked_list.sa` | （未移动，仍在原位） | 1146 | MOD | 1 行导入更新（`../vec.sa`→`vec/vec.sa`）；不建子目录的理由见 REPORT §2.2 |
| `sa_std/collections/linked_list.sal` | （未移动，仍在原位） | 10 | — | 无导入 |
| `sa_std/collections/prelude.sa` | （原位） | 7 | MOD | 7 行导入改为新子路径；成员不变 |
| `sa_std/collections/prelude.sal` | （原位） | 1 | MOD | `../collections.sal`→`collections.sal` |

## 2. string 域（15 个移动，含 1 个改名）

| 旧路径 | 新路径 | 行数 | 状态 | 备注 |
|---|---|---|---|---|
| `sa_std/string.sa` | `sa_std/string/string/string.sa` | 12241 | MV + SHIM | 10 行导入更新；691 个 `STRING_*` + 241 个 `STR_*` 宏；**未拆分** |
| `sa_std/string.sal` | `sa_std/string/string/string.sal` | 17 | MV + SHIM | 2 行导入更新（`alloc/vec.sal`、`ffi.sal`→`../../`） |
| `sa_std/string.sai` | `sa_std/string/string/string.sai` | 25 | MV + SHIM | 无导入；25 个 `sa_str_*/sa_string_*` extern |
| `sa_std/string_format.sa` | `sa_std/string/builder/string_format.sa` | 269 | MV + SHIM | 5 行导入更新；format 机制归入 builder |
| `sa_std/alloc/string.sa` | `sa_std/string/builder/str_from_const.sa` | 3 | MV + SHIM（改名） | 仅 `STR_FROM_CONST` 一个宏；改名已登记；旧路径 `alloc/string.sa` 留 shim |
| `sa_std/char.sa` | `sa_std/string/utf8/char.sa` | 1309 | MV + SHIM | 导入不变（`char.sal`、`ascii.sa` 同目录） |
| `sa_std/char.sal` | `sa_std/string/utf8/char.sal` | 50 | MV + SHIM | 无导入 |
| `sa_std/ascii.sa` | `sa_std/string/utf8/ascii.sa` | 2 | MV + SHIM | 2 行导入更新（`core/ascii.*`→`../../core/ascii.*`）；原为 core 的转发 shim |
| `sa_std/ascii.sal` | `sa_std/string/utf8/ascii.sal` | 1 | MV + SHIM | 1 行导入更新；原为 `@import "core/ascii.sal"` 的 shim |
| `sa_std/cstring.sa` | `sa_std/string/string/cstring.sa` | 3 | MV + SHIM | 2 行导入更新（`ffi.*`→`../../ffi.*`） |
| `sa_std/cstring.sal` | `sa_std/string/string/cstring.sal` | 2 | MV + SHIM | 1 行导入更新（`ffi.sal`→`../../ffi.sal`） |
| `sa_std/str.sla` | `sa_std/string/str.sla` | 38 | MV + SHIM | 2 行 `sa_std/` 导入更新；shim 用 `sa_std/` 前缀 |
| `sa_std/ts_string.sa` | `sa_std/string/ts/ts_string.sa` | 638 | MV + SHIM | 3 行导入更新（`string.sai`→`../string/string.sai` 等） |
| `sa_std/ts_unicode.sa` | `sa_std/string/ts/ts_unicode.sa` | 55 | MV + SHIM | 导入不变（`ts_unicode.sai` 同目录） |
| `sa_std/ts_unicode.sai` | `sa_std/string/ts/ts_unicode.sai` | 13 | MV + SHIM | 无导入；1 个 ICU extern `sa_unicode_normalize` |

## 3. text / encoding 域（0 个移动）

| 文件 | 状态 | 备注 |
|---|---|---|
| `sa_std/text/*`（6 个：`prelude.sa`、`prelude.sal`、`regex.sa`、`regex.sai`、`regex.sal`、`regex.sla`） | 未动 | 结构已是域目录形态；`regex.sa` 仅 2 行（见 DEF-07） |
| `sa_std/encoding/*`（12 个） | 未动 | 结构已是域目录形态；仅 `bitpack.sla:104` 1 行导入更新（`sa_std/vec.sa`→`sa_std/collections/vec/vec.sa`） |

## 4. 共享文件（仅本域导入行）

| 文件 | 改动 |
|---|---|
| `sa_std/prelude.sa` | 12 行本域导入改为规范路径（其余行原样） |
| `sa_std/prelude.sal` | 11 行本域导入改为规范路径（其余行原样） |

## 5. 未移动的相邻文件（登记，非本域或刻意保留）

| 文件 | 原因 |
|---|---|
| `sa_std/alloc/vec.sa`、`alloc/vec.sal`、`alloc/growvec.sa`、`alloc/growvec.sal`、`alloc/layout.sal` | alloc 运行时层，保留（REPORT §2.2） |
| `sa_std/hash.sa`（1486 行）、`sa_std/num.sa`、`sa_std/ptr.sa` | 共享原语，归属待定（DEF-09/03）；`num.sa` 明确不在本域 |
| `sa_std/core/hash.sa` | core 域文件，未动 |
| `sa_std/ffi.*`、`fmt.*`、`io.*` | 其他域，未动 |
| `sa_std/ts_array.sa` 等其余 `ts_*` | ts 兼容簇未整体划归本域，仅 `ts_string`/`ts_unicode` 移入 `string/ts/` |
