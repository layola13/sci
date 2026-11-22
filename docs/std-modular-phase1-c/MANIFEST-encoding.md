# 模块边界清单 — encoding 域

## 公共模块（Phase 1 零移动；仅 `bitpack.sla:104` 更新 1 行导入）

| 模块 | 内容 | 行数 | 公共入口 |
|---|---|---|---|
| `encoding/json.sa` | `JSON_*` 宏（包 `sa_json_*` extern） | 259 | `encoding/prelude.sa` |
| `encoding/json.sai` | `sa_json_*` extern 声明（u64 句柄约定） | 81 | 同胞自动注入 + 直接导入（`json.sla`、`jwt.sla`、`net_info.sla`、`tls_server.sla`） |
| `encoding/json.sal` | `SA_JSON_KIND_*`/`SA_JSON_TOKEN_*` 常量 | 35 | 同胞自动注入 |
| `encoding/json.sla` | SLA 层 JSON 包装 | 145 | 直接导入 |
| `encoding/base64.sai` | `sa_b64dec_simd` / `sa_deno_btoa` / `sa_deno_atob` 等 extern 声明 | 31 | 直接导入（`smtp.sla`、`jwt.sla`、`http_proxy.sla`） |
| `encoding/bitpack.sla` | bitpack 编解码（SLA，914 行） | 914 | 直接导入（`tests/bitpack_ops.sla`） |
| `encoding/toml.sai` | `sa_toml_*` extern 声明（u64 句柄） | 54 | 直接导入（`toml.sla`） |
| `encoding/toml.sla` | SLA 层 TOML 包装 | 65 | 直接导入 |
| `encoding/yaml.sai` | `sa_yaml_*` extern 声明（u64 句柄） | 76 | 直接导入（`yaml.sla`） |
| `encoding/yaml.sla` | SLA 层 YAML 包装 | 63 | 直接导入 |
| `encoding/prelude.sa` | 仅聚合 `json.sa`（1 行，无尾换行） | 1 | `sa_std/prelude.sa` |
| `encoding/prelude.sal` | **空文件（0 字节）** | 0 | `sa_std/prelude.sal` |

## 职责

- 数据格式编解码：JSON（SA 宏 + SLA）、TOML、YAML（SLA + Zig extern）、base64（extern only）、bitpack（SLA）。
- 注意与 `string/encoding/`（预留空）的区别：本域是**数据格式**（JSON/TOML/YAML/base64/bitpack）；`string/encoding/` 预留给**字符串编码**（UTF-8/UTF-16 等字符编码）。命名重叠已登记（REPORT §2.2），Phase 2 需确认 `string/encoding/` 是否改名（如 `string/codec/`）以免混淆。

## 允许的依赖方向

- ✅ `core/*`（`core/slice.sa` 等）。
- ✅ `collections/vec`（`bitpack.sla:104` 引用 `sa_std/collections/vec/vec.sa`，已更新为规范路径）。
- ✅ Zig 宿主 extern（`sa_json_*`、`sa_toml_*`、`sa_yaml_*`、`sa_b64*`、`sa_deno_*`）。
- ✅ `status.sla`、`math.sai`（`bitpack.sla:107-108`，域外基础模块）。
- ❌ 禁止：`io` 实现、`net`、`db`、`http`、`fs`。
- ⚠️ 已知例外（登记未修）：`encoding → collections/vec`（DEF-05，bitpack 需要 Vec；可接受或 Phase 2 复议）。

## 缺陷登记

- DEF-06：`encoding/prelude.sa` 只聚合 `json.sa`，toml/yaml/base64/bitpack 均未聚合；`encoding/prelude.sal` 为空文件。
- DEF-18：base64 没有 `.sa`/`.sla` 实现文件，只有 `.sai` extern 声明；编解码全靠宿主。
