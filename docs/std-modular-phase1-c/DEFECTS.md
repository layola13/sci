# 发现的缺陷清单（未修复）— 领域 C

> 约定：以下全部**只记录、未动手修复**（用户亲令：Phase 1 不修 bug）。行号为移动后路径；“移动前”指 HEAD `be42fa97` 的位置。严重度：高 = 破坏分层/可能影响正确性；中 = 边界不清/可维护性；低 = 文档/完整性。

## 分层倒置

### DEF-01（高）`core/hash.sa` 反向依赖 collections
- 位置：`sa_std/core/hash.sa:1-2`（`@import "../hashmap.sal"`、`@import "../hashmap.sa"`）。
- 描述：core 域的 `HASH_PTR` 宏 facade 直接依赖 collections 的 hashmap。core 应是底层，依赖方向倒置。移动后经顶层 `hashmap.sa` shim 解析，功能不受影响，但分层违规仍在。
- 归属：core 域；本任务未动（禁令：不动其他域文件）。

### DEF-02（中）`string.sa` 依赖 `hash.sa` 与 `fmt.sai`
- 位置：`sa_std/string/string/string.sa:8-9`（移动前 `sa_std/string.sa:8-9`：`@import "fmt.sai"`、`@import "hash.sa"`）。
- 描述：string 域“只依赖 core”的目标不成立。`fmt.sai` 只是 extern 声明头（无代码依赖），影响小；`hash.sa` 是 1486 行真实代码依赖。
- 建议：Phase 2 确认 `hash.sa` 归属（DEF-09）后复议。

### DEF-03（中）collections 依赖 `num.sa`（core 之外）
- 位置：`collections/hashmap/hashmap.sa:6`、`collections/hashset/hashset.sa:6`、`collections/btree/btree_map.sa:5`、`collections/heap/binary_heap.sa:8`、`collections/deque/vec_deque.sa:8`、`alloc/vec.sa:27`、`alloc/growvec.sa:3`（均 `@import "num.sa"`，已更新为 `../../num.sa`）。
- 描述：7 处引用。`num.sa` 是数值原语（自身又引 `hash.sa` 与 `cmp.sal`），事实上的 core 邻层，但名义上不在 core 内。
- 建议：把 `num.sa` 承认为允许方向，或将其数值原语并入 core（需 num 域确认）。

### DEF-04（中）`core/iter.sa` 依赖 `vec_runtime_macros.sa`
- 位置：`sa_std/core/iter.sa:4`（`@import "../vec_runtime_macros.sa"`）。
- 描述：core 反向依赖 collections 的 `ITER_VEC_*` 宏。移动后经顶层 shim 解析，功能不受影响；规范路径更新属于 core 域，本任务未动。

### DEF-05（低）`encoding/bitpack.sla` 依赖 `collections/vec`
- 位置：`sa_std/encoding/bitpack.sla:104-108`（`sa_std/collections/vec/vec.sa` 已更新为规范路径；另有 `sa_std/core/slice.sa`、`sa_std/ptr.sa`、`sa_std/status.sla`、`sa_std/math.sai`）。
- 描述：encoding → collections 边。bitpack 需要 Vec，可接受；登记在案供 Phase 2 复议。

## 归属未定

### DEF-09（高）两个同名 `hash.sa`，内容不同
- 位置：`sa_std/hash.sa`（1486 行，`BUILD_HASHER_DEFAULT_*` 宏实现）与 `sa_std/core/hash.sa`（小 facade，包 `../hashmap.sa`）。
- 描述：同名不同物，易混淆；`hash.sa` 的归属（`core/hash/` 还是 `collections/hash/`）未定，本次未移动。`vec.sa`、`string.sa`、`num.sa`、`array.sa`、`ffi.sa` 均引顶层 `hash.sa`。

### DEF-15（中）`alloc/` 瘦身后归属未定
- 位置：`sa_std/alloc/` 现只剩 `vec.sa`、`vec.sal`、`growvec.sa`、`growvec.sal`、`layout.sal`、`prelude.sa`、`prelude.sal` + 1 个 shim（`string.sa`）。
- 描述：`alloc/` 是 collections 与 string 共用的运行时层；Phase 2 需决定保留为独立运行时层还是并入 core。

### DEF-16（低）`string/encoding/` 子目录预留为空
- 描述：提案的 `string/encoding/` 无文件可填——UTF-8/UTF-16 编解码仍在 12241 行的 `string.sa` 内。git 不跟踪空目录，故未建目录。填充需拆 `string.sa`，属 Phase 2+。

### DEF-17（低）GrowVec 未入任何 prelude
- 位置：`sa_std/collections/prelude.sa`（7 成员，无 growvec）；`sa_std/prelude.sa` 亦不导入 `growvec.sa`。
- 描述：GrowVec 只能直接导入，无聚合入口。本次刻意未加入 prelude（聚合入口变更属公共面变更，留待决定）。

## 完整性 / 结构

### DEF-06（中）`encoding/prelude.sa` 只聚合 json；`prelude.sal` 为空
- 位置：`sa_std/encoding/prelude.sa`（1 行，仅 `@import "json.sa"`）；`sa_std/encoding/prelude.sal`（0 字节空文件）。
- 描述：toml/yaml/base64/bitpack 均未聚合；空 `.sal` 伴生文件无内容。

### DEF-07（低）`text/regex.sa` 是 2 行 stub，无 SA 实现
- 位置：`sa_std/text/regex.sa`（仅 `@import "regex.sal"` + `@import "regex.sai"`）。
- 描述：regex 能力全由 Zig 宿主提供；SA 侧无可移植实现。现状可工作，但 text 域的 SA 侧实现为空。

### DEF-08（中）`string.sa` 12241 行单体，未拆分
- 位置：`sa_std/string/string/string.sa`（691 个 `STRING_*` + 241 个 `STR_*` 宏；154 处 `UTF16` 提及；`STRING_BUF_*` 构建器宏与 UTF-8/UTF-16/解析混排）。
- 描述：按 Phase 1 原则刻意未拆分。拆分方案与 `string/encoding/` 填充留给 Phase 2。

### DEF-10（低）`vec.sal` 与 `alloc/vec.sal` 同名不同内容
- 位置：`sa_std/collections/vec/vec.sal`（1 行，`Vec_data = +0`）与 `sa_std/alloc/vec.sal`（3 行，`Vec_SIZE/ptr/cap/len`）。
- 描述：两份布局常量互补而非重复；本次各自随所属 `.sa` 移动，未合并。合并需确认 `Vec_data` 与 `Vec_SIZE` 族无冲突，留给 Phase 2。

### DEF-11（低）`string.sal` 依赖 `ffi.sal`
- 位置：`sa_std/string/string/string.sal:1-2`（`@import "../../alloc/vec.sal"`、`@import "../../ffi.sal"`）。
- 描述：string 布局层依赖 ffi 布局层。影响限于 `.sal` 常量。

### DEF-12（中）`cstring` 依赖 `ffi.sa` 实代码
- 位置：`sa_std/string/string/cstring.sa:2-3`（`@import "../../ffi.sal"`、`@import "../../ffi.sa"`）。
- 描述：CString 本质上需要 FFI 实现；但这使 string → ffi 出现代码级依赖，与“只依赖 core”目标冲突。登记为固有例外，Phase 2 确认。

### DEF-13（低）`ts_string` 依赖域外 `ts_array.sa`
- 位置：`sa_std/string/ts/ts_string.sa:15`（`@import "../../ts_array.sa"`；另 `:14` 引 `../string/string.sai`、`:16` 引 `../../fmt.sai`）。
- 描述：`ts_*` 兼容簇（`ts_array`、`ts_object`、`ts_jsval` 等）仍在顶层，未整体划归本域；`string/ts/` 只移了其中两个文件。

### DEF-14（低）`string_format.sa` 被 3 个域外 `.sla` 引用
- 位置：`sa_std/url.sla`、`sa_std/ip.sla`、`sa_std/http_proxy.sla` 引用 `string_format.sa`（经顶层 shim 解析）。
- 描述：功能不受影响；规范路径更新属于各引用方，本任务未动。

### DEF-18（低）base64 只有 `.sai`，无 `.sa`/`.sla`
- 位置：`sa_std/encoding/base64.sai`（31 行 extern 声明）；引用方：`sa_std/smtp.sla`、`sa_std/jwt.sla`、`sa_std/http_proxy.sla`、`tests/jwt.sla`。
- 描述：base64 编解码全靠宿主 extern（`sa_b64dec_simd`、`sa_deno_btoa/atob` 等），SA 侧无实现。

### DEF-19（低）增长契约注释三处重复
- 位置：`sa_std/alloc/vec.sa` 文件头、`sa_std/collections/vec/vec_grow.sla` 文件头、`sa_std/collections/vec/vec_packed.sla` 文件头（几何增长 0→4 后翻倍、exact reserve 禁增量增长等同一契约文本）。
- 描述：文档重复，存在漂移风险（改一处忘两处）。只登记，未统一。

### DEF-20（低）`str.sla` 与 `vec_grow.sla` 仓内 0 引用者
- 描述：grep 显示没有任何 `.sa`/`.sla` 文件导入 `str.sla` 或 `vec_grow.sla`（`vec_packed.sla` 仅被 `vec_grow.sla` 导入）。疑似入口点文件；未删除，未调查用途。

### DEF-21（低）`sa_std/prelude.sal` 混入一行 `@import "array.sa"`
- 位置：`sa_std/prelude.sal`（`@import "array.sa"`，其余行均为 `.sal`/`.sai`）。
- 描述：布局伴生文件导入代码文件，疑似历史遗留；本任务未动该行（不属本域导入行），只登记。
