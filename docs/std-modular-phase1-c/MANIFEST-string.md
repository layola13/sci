# 模块边界清单 — string 域

## 公共模块

| 模块（规范路径） | 内容 | 行数 | 公共入口 |
|---|---|---|---|
| `string/string/string.sa` | `String`/`str` 宏全集（691 个 `STRING_*` + 241 个 `STR_*` 宏） | 12241 | `sa_std/prelude.sa` |
| `string/string/string.sal` | `FromUtf8Error`/`FromUtf16Error`/`ParseBoolError` 布局常量 | 17 | 同胞自动注入 |
| `string/string/string.sai` | `sa_str_*`/`sa_string_*` extern 声明（25 个） | 25 | 同胞自动注入 + 直接导入（`io.sa`、`ffi.sa` 等） |
| `string/string/cstring.sa` | CStr/CString facade（包 `ffi.sa`） | 3 | `sa_std/prelude.sa`、`ffi/prelude.sa`（经 shim） |
| `string/string/cstring.sal` | C string 布局别名 | 2 | 同胞自动注入 |
| `string/builder/string_format.sa` | `format!` 机制 | 269 | `string.sa`、`sa_std/prelude.sa`；另被 `url.sla`/`ip.sla`/`http_proxy.sla` 引用（经 shim） |
| `string/builder/str_from_const.sa` | `STR_FROM_CONST` 一个宏（原 `alloc/string.sa` 改名） | 3 | `demos/*/15_string_bytes`（经 shim） |
| `string/utf8/char.sa` | `char` 标量值宏（`CHAR_*`） | 1309 | `string.sa`、`sa_std/prelude.sa` |
| `string/utf8/char.sal` | `CHAR_*` 常量与 `ParseCharError` 等布局 | 50 | 同胞自动注入 |
| `string/utf8/ascii.sa` | 转发 shim → `core/ascii.sa`（784 行实现在 core） | 2 | `string.sa`、`char.sa`、`core/prelude.sa`（经 shim） |
| `string/utf8/ascii.sal` | 转发 shim → `core/ascii.sal` | 1 | 同胞自动注入 |
| `string/ts/ts_string.sa` | tsgosa 薄柄字符串操作（`@ts_str_*`） | 638 | `ts_object.sa`/`ts_jsval.sa`（经 shim）、`demos/*/335_*`（经 shim） |
| `string/ts/ts_unicode.sa` | Unicode 归一化 SA 包装（ICU extern） | 55 | 直接导入 |
| `string/ts/ts_unicode.sai` | `sa_unicode_normalize` extern 声明 | 13 | 同胞自动注入 |
| `string/str.sla` | SLA 层 `str_from_utf8` 等辅助 | 38 | 直接导入（仓内 0 引用者，入口点） |
| （预留）`string/encoding/` | 空，未建目录 | — | UTF-8/UTF-16 编解码仍在 `string.sa` 内，拆分属 Phase 2+（DEF-16） |

聚合入口：本域暂无 `string/prelude.sa`（此前也没有；`sa_std/prelude.sa` 直接聚合 `string.sa`、`string_format.sa`、`char.sa`、`ascii.sa`、`cstring.sa`）。是否新建 `string/prelude.sa` 属 Phase 2 议题。

## 职责

- `String`/`str` 类型与全部 `STR_*`/`STRING_*` 宏（含 `STRING_BUF_*` 构建器宏、UTF-8 校验/转换宏、UTF-16 相关宏）。
- `char`（Unicode 标量值）与 ASCII facade。
- `CString`/`CStr`（FFI 字符串门面）。
- `format!` 机制与 `STR_FROM_CONST` 常量构造宏。
- tsgosa 兼容层（`string/ts/`）：只服务 tsgosa 移植调用点，不属通用公共面。

## 允许的依赖方向

- ✅ `core/*`：`core/slice.*`、`core/ascii.*`（经 `string/utf8/ascii.sa` shim）。
- ✅ `collections/vec/*`：`vec.sa`、`vec.sal`（字符串构建的底层容器）。
- ✅ `alloc/*`：`alloc/vec.sal`（经 `string.sal` 的布局依赖）。
- ✅ 各 `.sai` extern 声明头：`fmt.sai`、`io.sai`、`string.sai`（声明，无代码依赖）。
- ✅ 顶层 `hash.sa`：哈希器实现（`string.sa:9`，归属待定，DEF-09）。
- ❌ 禁止：`io` 实现、`net`、`db`、`http`、`fs`、`text`、`encoding`。
- ⚠️ 已知例外（登记未修）：`cstring` → `ffi.sa` 实代码（DEF-12，CString 本质需要 FFI）；`string.sal` → `ffi.sal`（DEF-11）；`ts_string` → `ts_array.sa`（DEF-13，域外 ts 簇）。

## 不拆分的决定

`string.sa` 12241 行是 `str` + `String` + `STRING_BUF` + UTF-8/UTF-16 + 解析/格式化辅助的混合单体。Phase 1 只定边界、不拆文件（用户亲令：先整完模块边界，不要边整边修；提案亦言“是定模块边界与依赖方向，不是单纯把大文件拆成小文件”）。拆分方案（`string/`、`builder/`、`utf8/`、`encoding/` 四子域的进一步落地）留给 Phase 2，届时 `string/encoding/` 子目录才有内容可填。
