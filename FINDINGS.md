# sa_std MySQL 客户端线 — 交付记录

- 线：STD 第四批 · MySQL 客户端（用户 2026-10-28 20:36 批准开线）
- 基点：sci `0dc7aea4`（ls-remote 核到的远端 tip；= 28fd2ceb + 一笔 ts 垫片提交）
- 本机 staging：`~/workspace/std-mysql-local/`，分支 `mysql-client-v1`
  - `00389261` 运行时 + .sai/.sla + sa_std.h + sa_std.zig 接线
  - `9ac7b297` 真服务器活验（tests/，不进默认套件）
- 盒上 worktree：`/content/sci-mysql-wt`（@00389261 + 活验文件 cat 管道同步、sha256 双确认）；基线 worktree `/content/sci-mysql-base`（@0dc7aea4 原样）

## 交付物

| 文件 | 内容 |
|---|---|
| `src/runtime/sa_mysql_client.zig` | 纯 Zig MySQL 协议 v10 客户端运行时（进 libsa_std.a），含模块内单测 |
| `sa_std/mysql_client.sai` | SA 面 extern 声明 + 完整契约头注（句柄/错误码/值模型/不支持清单） |
| `sa_std/mysql_client.sla` | 列类型码常量（SA_MYSQL_TYPE_*），并 @import .sai |
| `src/runtime/sa_std.h` | C 声明 30 个 |
| `src/runtime/sa_std.zig` | comptime 强制引用块新增 30 行 |
| `tests/mysql_client_live.sla` + `tests/run_mysql_live_tests.sh` | 真 MySQL 8.0.46 活验（独立运行，不进默认套件） |

## API 面（30 个 extern）

连接：`sa_mysql_supported`、`sa_mysql_connect`、`sa_mysql_close`、`sa_mysql_ping`；
文本协议：`sa_mysql_query`；
预处理：`sa_mysql_prepare`、`sa_mysql_stmt_bind_null/i64/u64/f64/bytes`、`sa_mysql_stmt_param_count`、`sa_mysql_stmt_execute`、`sa_mysql_stmt_close`；
错误/会话：`sa_mysql_errno`、`sa_mysql_sqlstate`、`sa_mysql_error_message`、`sa_mysql_server_version`、`sa_mysql_connection_id`；
结果：`sa_mysql_result_free`、`sa_mysql_result_has_result_set`、`sa_mysql_result_column_count`、`sa_mysql_result_column_name`、`sa_mysql_result_column_type`、`sa_mysql_result_row_count`、`sa_mysql_result_next`、`sa_mysql_result_value`、`sa_mysql_affected_rows`、`sa_mysql_last_insert_id`、`sa_mysql_result_warnings`。

状态码：0 OK；-1/-5/-12/-22 沿 sci 惯例；MySQL 专用：**-101** 服务器 ERR 包（errno/SQLSTATE/message 经连接访问器原样带回）、**-102** 协议错误（连接已死）、**-103** caching_sha2 全量认证需 TLS 或 RSA（v1 显式拒绝）、**-104** 未实现的认证插件。

## 认证路径覆盖表

| 路径 | 状态 | 证据 |
|---|---|---|
| mysql_native_password（含 auth switch 切换） | ✅ 实现 | 扰码向量单测（hashlib 独立计算）+ 假服务器逐字节校验 + 真服务器活验 |
| caching_sha2_password fast path | ✅ 实现 | 扰码向量单测 + 真服务器活验（官方客户端预热缓存后登录成功） |
| caching_sha2_password full auth（冷缓存首登） | ⛔ v1 明确不支持 → **-103** | 真服务器活验（冷账户首登得 -103）；依赖加密线 RSA 或未来 TLS 通道 |
| sha256_password / mysql_clear_password / 对话式插件 | ⛔ 未实现 → **-104** | 代码路径显式返回 |
| 空口令账户 | ✅（空 token，按协议） | 扰码函数空口令分支 |

## 类型覆盖表（结果值统一为文本形态字节）

| 来源 | 类型 | 处理 |
|---|---|---|
| 文本协议 | 全部 | 服务器文本渲染原样透传 |
| 二进制协议 | TINY/SHORT/LONG/INT24/LONGLONG/YEAR | 按列 UNSIGNED 标志解码 → 十进制文本 |
| 二进制协议 | FLOAT/DOUBLE | 最短往返十进制 |
| 二进制协议 | DECIMAL/NEWDECIMAL | lenenc 字节原样（即文本形态） |
| 二进制协议 | DATE/DATETIME/TIMESTAMP | 二进制字段 → ISO 文本（微秒尾零裁剪，同 MySQL 文本渲染） |
| 二进制协议 | TIME | 同上（小时可 >24、负号保留） |
| 二进制协议 | VARCHAR/VAR_STRING/STRING/BLOB 全宽/ENUM/SET/JSON | lenenc 字节原样 |
| 二进制协议 | BIT / GEOMETRY | **原始字节**（.sai 已注明） |
| 两协议 | NULL | out_is_null 报告，绝不伪装成空串 |

## 未覆盖项（明确清单，全部显式拒绝、无静默降级）

1. caching_sha2 full auth（RSA 口令加密）——等加密线 RSA 落地后接（或 TLS 通道）。
2. TLS 传输（`CLIENT_SSL`）——v1 明文 TCP；不可信网络勿用（.sai 已警告）。
3. LOAD DATA LOCAL INFILE——服务器请求即 -1 并断开（协议无安全拒绝位）。
4. 多语句（从不协商 CLIENT_MULTI_STATEMENTS）；存储过程多结果集只保留第一个、其余排空丢弃（.sai 已注明，勿 CALL 需要后续结果集的过程）。
5. COM_STMT_SEND_LONG_DATA（绑定值一律内联发送）、预处理游标/COM_STMT_FETCH。
6. 连接属性（_client_name 等）、查询超时/中断、自动重连、连接池、Unix socket 传输（v1 仅 TCP）。
7. 结果集全量物化（无流式 fetch）——大结果集内存与结果成正比，v1 已知取舍。

## 新增原语/依赖清单（供主会话集成去重）

- 本线**自含**：SHA-1/SHA-256 扰码在运行时内用 `std.crypto.hash.Sha1` / `sha2.Sha256` 实现，**未新增任何 std 级 crypto extern**，与加密线的原始摘要原语无符号冲突；集成时无需去重。
- extern 前缀 `sa_mysql_*`（30 个），与既有面无同名。
- 未改 sa_plugin_sla；未动他人 worktree。

## 验证记录

- 模块单测（本机 zig test 直编模块）：6/6 —— lenenc 边界、双扰码已知向量、ERR 包记录、二进制时间/浮点/整数解码、脚本化假服务器端到端（服务器侧逐字节校验 token）。
- 盒上 sa-std-unit 名字集对基线：基线（sci-mysql-base @0dc7aea4）231/232，失败集 = {`sa_crypto.test.keyring: library availability is reported honestly`}（环境项）；本线（sci-mysql-wt）**237/238，失败集与基线逐名相同、零新增**，总数 +6 即本线 6 个模块单测全过（日志 /content/mysql-base-unit.log、/content/mysql-wt-unit.log）。
- 盒上 sa-std-static + nm 符号核对：`zig build sa-std-static` 后 `artifacts/sa_std/libsa_std.a` 中 `T sa_mysql_*` 恰 **30 个**，与 .sai 声明一一对应。
- 真服务器活验（MySQL **8.0.46-0ubuntu0.24.04.4**，盒上 apt 装、loopback 127.0.0.1:13306、一次性 datadir）：**6/6 PASS**（`tests/run_mysql_live_tests.sh`，日志 /content/mysql-live.log）：
  - `native auth: DDL, DML and typed select round trip` ✅（逐值核对 INT/VARCHAR/DECIMAL/DOUBLE/DATETIME/NULL/UPDATE affected/ping）
  - `prepared statements: bindings and binary row decoding` ✅（5 参数 INSERT + 二进制行 SELECT 逐值 + u64max 绑定往返）
  - `server errors surface errno and sqlstate verbatim` ✅（1146/42S02 查询错误 + 1045/28000 错口令登录，handle 保留可读错误）
  - `caching_sha2 fast path succeeds once the cache is warm` ✅（官方客户端预热后登录 + SELECT 1 + server_version 非空）
  - `caching_sha2 cold cache demands full auth and v1 refuses with -103` ✅
  - `close and reconnect` ✅
- 活验联调中修正的三个测试侧问题（运行时零改动）：① runner 的 `--mysql-native-password=ON` 探测 grep 误命中 `mysql-native-password-proxy-users`——8.0 无此启动选项且原生插件默认在册，已删除该旗标（setup SQL 的 `IDENTIFIED WITH mysql_native_password` 仍是大声失败兜底）；② u64max 字面量超 SLA 词法器有符号范围（error.InvalidCharacter），改算术构造；③ 测试文件需显式 `@import "sa_std/string.sa"`（STR_PTR/STR_LEN）与 `"sa_std/ptr.sa"`（PTR_BYTE_ADD），与既有测试惯例一致。
