# fmt 域边界清单（MANIFEST）

域入口：`sa_std/fmt/prelude.sa`（.sa 聚合）、`sa_std/fmt/prelude.sal`（布局聚合）。
旧路径 shim：`sa_std/fmt.sa`、`fmt.sai`、`fmt.sal`、`string_format.sa`。

## 1. 公共模块

| 模块 | 文件 | 职责 | 宏数 |
|---|---|---|---|
| fmt（契约） | fmt/fmt.sai | Zig 后端 `sa_fmt_*` 的 @extern 声明（i64/u64/f64/bool/bytes + _into + buffer） | — |
| fmt（布局） | fmt/fmt.sal | SA_FMT_* 状态码、SA_FMT_BASE_*、SaFmtBuffer/SaFmtOptions/FmtResult 布局；`@import "../core/result.sal"` | — |
| fmt/format | fmt/format/string_format.sa | STRFMT_*（15，sa_fmt_* 的缓冲包装）+ FORMAT_*（25，builder + FORMAT_WRITE*/WRITELN*） | 40 |
| fmt/format | fmt/format/format.sa | FORMAT_INT（自 io.sa 移入；调 `@sa_fmt_i64`） | 1 |
| fmt/display | fmt/display/prelude.sa | **占位，无内容**（见 §5） | 0 |
| fmt/debug | fmt/debug/prelude.sa | **占位，无内容**（见 §5） | 0 |

合计：41 个宏。

## 2. 职责

- 标量 → 文本/缓冲：整数（多进制）、浮点（精度）、布尔、字节串；原地写入（_into）与持有式缓冲（SaFmtBuffer）。
- 格式化 builder：FORMAT_BEGIN/PUSH_*/AS_STR/FREE、FORMAT_*_TO_STRING、FORMAT_WRITE*/WRITELN*（写 io 句柄）。
- 不负责：打印到 stdout（io/print 域）、字符串类型本身（string 域）、解析（不在本域）。

## 3. 允许的依赖方向

```
fmt/format -> fmt（fmt.sai）、io（io.sai，仅 FORMAT_WRITE_* 的 sa_io_write_all）、
              core（slice/mem）、vec（FORMAT_BEGIN 的缓冲）
fmt 整体  -> core、vec、io（仅 .sai 契约，不含 io 宏）
fmt 整体 -/-> net、db、http、sync、time、os（FORMAT_INT 移入后，io→fmt 边已消除；
              fmt 不依赖 os/fd）
```

- fmt 依赖 core；fmt→io 是单向边（写出方向），io 不再反向依赖 fmt（原 io.sa 的 FORMAT_INT 是唯一的 io→fmt 边，已随宏移入 fmt）。
- 反向依赖（谁依赖 fmt）：io（已消除）、string.sa、ts_string.sa、ip.sla、url.sla、http_proxy.sla（均经 fmt.sai / string_format.sa，已改到新路径）。

## 4. 内部依赖图

- string_format.sa：STRFMT_* → sa_fmt_*（fmt.sai）；FORMAT_PUSH_* → sa_fmt_* + sa_vec_*（vec.sa）；
  FORMAT_WRITE_* → sa_io_write_all（io.sai）+ sa_fmt_*；FORMAT_*_TO_STRING → STRFMT_*（内部）。
- format.sa：FORMAT_INT → sa_fmt_i64（fmt.sai），无 EXPAND。

## 5. display / debug 为空的原因（已核查）

对整个 sa_std（364 个文件，.sa/.sai/.sal/.sla）grep `\b(Display|Debug)\b`：**零命中**。
SA 标准库目前没有任何 Display/Debug trait、宏或类型。用户提案的 fmt/display/、fmt/debug/ 子目录
是目标结构中的预留位置，本次只建目录 + 占位 prelude.sa（内含说明注释、无 import、无宏），
待 Display/Debug API 真正落地时再填内容。不要把 FORMAT_* 宏改名充数。
另见 DEFECTS.md D7：fmt.sal 里的 FmtResult/SaFmtBuffer/SA_FMT_* 目前全仓无使用者（死布局面，见 D3）。

## 6. 边界规则

1. 新格式化宏按前缀归属：STRFMT_*/FORMAT_*（format）；将来 Display_*（display）、Debug_*（debug）。
2. fmt.sai/fmt.sal 是域内唯一契约/布局文件；子模块不得私自声明 `sa_fmt_*` @extern。
3. fmt 不得新增对 os/net/db/http/sync/time 的依赖；对 io 的依赖只允许经 io.sai 的写出调用，不得 EXPAND io 宏。
4. 旧路径 shim 不得删除（string.sa 等仓内引用已改新路径，但 tests/demos 仍可能用旧路径；删除前须全仓核查）。
