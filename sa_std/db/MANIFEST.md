# db 域边界清单（MANIFEST）

- 域：数据库（database clients / embedded storage / auth tokens）
- 位置：`sa_std/db/`
- Phase 1 状态：2026-11-22 已整理（分支 `sa-optimize`，工作仓 `sci2-agentS1F`，未 commit）
- 负责人域：F（db + crypto + testing + tree_sitter + 总清单）

## 1. 职责

本域提供 SA 程序访问数据库与签发/校验认证令牌的能力：

- 有线协议客户端：MySQL/MariaDB、PostgreSQL、Redis（RESP）。
- 嵌入式存储门面：SQLite（经 Node 插件 extern）。
- 认证令牌：JWT（RFC 7519）签发与校验。

本域不提供：通用 key-value 抽象、ORM、迁移工具、连接池（均无文件，先记为缺口，不在 Phase 1 新建）。

## 2. 结构

```
sa_std/db/
  prelude.sa          # SA 侧公共面：两个 .sai + plugin_sqlite.sa（见 §5）
  prelude.sal         # 空文件（域内无 .sal 布局伴生文件；空 prelude.sal 有 encoding/prelude.sal 先例）
  core/               # 客户端核心面
    mysql_client.sai  # MySQL/MariaDB wire v10 extern 契约（Zig 实现见 §4）
    mysql_client.sla  # 列类型码 SA_MYSQL_TYPE_* 常量（import 本域 .sai）
    postgres.sai      # PostgreSQL wire v3 extern 契约（Zig 实现见 §4）
    postgres.sla      # import 面（纯转发 .sai，沿 plugin_sqlite.sla 先例）
    jwt.sla           # JWT HS256/RS256 签发与校验（SLA）
  query/              # 查询/命令面
    redis.sla         # RESP 编解码 + Redis 客户端（GET/SET/HASH/LIST/SET/ZSET/SCAN/EVAL/MULTI…）
  storage/            # 嵌入式存储面
    plugin_sqlite.sa  # SQLite 同步门面宏 SA_SQLITE_*（经 sa_node_plugin_sqlite_* extern）
    plugin_sqlite.sla # import 面（纯转发 .sa）
  transaction/        # 预留，空（见 §6）
  index/              # 预留，空（见 §6）
```

### 模块映射表（旧路径 → 新路径）

| 旧路径 | 新路径 | 行数 | 说明 |
|---|---|---|---|
| `sa_std/redis.sla` | `db/query/redis.sla` | 1923 | RESP 客户端；见 §3 例外（依赖 net） |
| `sa_std/mysql_client.sai` | `db/core/mysql_client.sai` | 155 | 有线客户端契约；无 shim（见 §7） |
| `sa_std/mysql_client.sla` | `db/core/mysql_client.sla` | 55 | 列类型常量；旧路径留 shim |
| `sa_std/postgres.sai` | `db/core/postgres.sai` | 28 | 有线客户端契约；无 shim（见 §7） |
| `sa_std/postgres.sla` | `db/core/postgres.sla` | 6 | import 面；旧路径留 shim |
| `sa_std/plugin_sqlite.sa` | `db/storage/plugin_sqlite.sa` | 106 | SQLite 门面宏；旧路径留 shim |
| `sa_std/plugin_sqlite.sla` | `db/storage/plugin_sqlite.sla` | 2 | import 面；旧路径留 shim |
| `sa_std/jwt.sla` | `db/core/jwt.sla` | 596 | JWT；旧路径留 shim；归属见 §8 待定 |

附带改动（移动必需的路径更新，非修 bug）：

- `db/core/mysql_client.sla`：`@import "sa_std/mysql_client.sai"` → `"sa_std/db/core/mysql_client.sai"`。
- `db/core/postgres.sla`：同上（postgres）。
- `db/core/jwt.sla`：`@import "sa_std/crypto.sai"` → `"sa_std/crypto/crypto.sai"`。
- `db/storage/plugin_sqlite.sla`：`@import "sa_std/plugin_sqlite.sa"` → `"sa_std/db/storage/plugin_sqlite.sa"`。

## 3. 依赖方向

允许依赖：**core**（`core/slice.sa`、布局 `.sal` 等）。

已声明的例外（边界事实，不在 Phase 1 改动）：

| 文件 | 依赖 | 说明 |
|---|---|---|
| `db/query/redis.sla` | `sa_std/net.sai` | TCP 传输：`sa_std_net_tcp_connect` / `sa_std_net_tcp_stream_read|write|close|set_read_timeout`。Redis 是网络客户端，纯 core 依赖做不到；传输层隔离为未来拆分候选（RESP 纯编解码 vs TCP 客户端，见 §8）。 |
| `db/core/jwt.sla` | `sa_std/crypto/crypto.sai`、`sa_std/encoding/base64.sai`、`sa_std/encoding/json.sai`、`sa_std/time.sai` | JWT 本质是 crypto 应用：HMAC/RSA 在 crypto.sai，base64url 在 encoding，exp/nbf 读 time。另依赖 `string.sa`、`vec.sa`、`core/slice.sa`、`ptr.sa`、`status.sla`（均未移动）。 |
| `db/storage/plugin_sqlite.sa` | `sa_node_plugin_sqlite_*` extern（Node 插件） | 无 SA 侧 import；调用方须先 import `node_extra.sai`（见该文件头注释）。 |

禁止依赖：io、net（除 redis 外）、http、task、sync。本域文件之间只允许 `core → query/storage` 单向（目前无域内交叉 import；`db/prelude.sa` 的聚合不算依赖）。

## 4. Zig 宿主侧（只记录，不动 `src/`）

- `mysql_client.sai` 的 extern 由 `src/runtime/sa_mysql_client*.zig` 实现（纯 Zig wire v10，无外部库）。
- `postgres.sai` 的 extern 由 `src/runtime/sa_pg.zig` 实现。
- `plugin_sqlite.sa` 的 extern（`sa_node_plugin_sqlite_*`）由 Node 插件提供，非 `src/runtime`。
- `jwt.sla` / `redis.sla` 是纯 SLA，无新增 extern；`redis.sla` 复用 `net.sai` 已有的 TCP extern。
- 核查结论：`src/` 与 `build.zig` 中没有按文件路径硬编码引用上述 `.sai`/`.sla` 的地方（只在注释中出现路径字面量）；extern 按符号名链接，不按文件路径。因此移动文件不要求 Zig 侧改名。**但 Phase 2 必须构建验证**：确认 `sa_std` 的安装/定位按目录树整体处理、新子目录能被编译器找到（`SA_STD_DIR` 机制，见 `src/cli/compile.zig`）。

## 5. Prelude 与公共面

- `db/prelude.sa` 聚合 SA 侧公共面：`core/mysql_client.sai`、`core/postgres.sai`、`storage/plugin_sqlite.sa`。沿用各子目录既有 prelude 模式（相对路径 `@import` 聚合）。
- `.sla` 文件（`query/redis.sla`、`core/mysql_client.sla`、`core/postgres.sla`、`core/jwt.sla`、`storage/plugin_sqlite.sla`）**不进 `prelude.sa`**：全仓核查，零个 `.sa` 文件 import `.sla` 文件，且不存在 `prelude.sla` 先例。`.sla` 按完整新路径单独 import。
- 顶层 `sa_std/prelude.sa` / `prelude.sal` 未改动：它们 import 的 `hash.sa` / `hash.sal` 已改为经旧路径 shim 转发（`crypto/hash/`），门面仍成立。是否把 `db/prelude.sa` 纳入顶层门面，是 Phase 2 决策（见 §8）。

## 6. 预留子目录

- `db/transaction/`（空，仅 `README.md`）：事务面预留。现存事务能力（Redis MULTI/EXEC/DISCARD）仍在 `query/redis.sla` 内，独立事务模块待 Phase 2 落地。
- `db/index/`（空，仅 `README.md`）：索引面预留。`sa_std` 现无索引模块。

## 7. 兼容策略

- 旧路径留薄 shim（2 行：注释 + `@import`），沿用仓内既有模式（`option.sa` → `core/option.sa` 等约 40 处先例）。shim 清单：`redis.sla`、`mysql_client.sla`、`postgres.sla`、`plugin_sqlite.sa`、`plugin_sqlite.sla`、`jwt.sla`。
- **`.sai` 文件无 shim**：全仓核查，零个 `.sai` 文件包含 `@import`，`.sai` shim 未经验证，不造先例。`.sai` 的 import 方极少且全部可控：
  - `mysql_client.sai`：仅 `db/core/mysql_client.sla` import（已同步更新）。
  - `postgres.sai`：仅 `db/core/postgres.sla` import（已同步更新）。
  - 因此 `.sai` 移动不需要外部改动。`tests/` import 的是 `.sla`（经 shim 兼容），未动 `tests/`。
- 引用方核查（`@import` 全仓扫描，排除 `.zig-cache`）：`tests/redis_wire.sla`、`tests/redis_client_loopback.sla`、`tests/mysql_client_live.sla`、`tests/jwt.sla` 仍用旧路径 import，经 shim 解析，静态检查 0 悬空（见总清单 §静态检查）。

## 8. 待定决策（Phase 2，不在 Phase 1 裁决）

1. **jwt.sla 的归属**：现按任务指派放在 `db/core/`。它本质是 crypto 应用（依赖 crypto + encoding + time），候选归属另有 `crypto/`（或未来 `crypto/auth/`）。Phase 2 需一次裁决后定点，不再搬移。
2. **redis.sla 的拆分候选**：RESP 纯编解码与 TCP 客户端合在一个文件（1923 行）。若拆，编解码留 `query/`、客户端进 `core/`；拆分本身是 Phase 2+ 工作，Phase 1 只定边界。
3. **顶层门面**：是否把 `db/prelude.sa` 纳入 `sa_std/prelude.sa`。
4. **transaction/ 与 index/ 的落地时机**：有首个事务/索引模块时再建文件，建文件时同步更新本清单。

## 9. 发现的问题（未修复，仅记录）

按用户亲令，Phase 1 只记录、不修复：

1. `db/query/redis.sla` 依赖 `net.sai`，与“db 只依赖 core”的目标方向冲突（见 §3 例外表）。这是结构事实，不是偶然 import；修法是拆分传输层，属 Phase 2 工作。
2. `db/core/mysql_client.sai` 头注释记载：`caching_sha2_password` 全量认证在 v1 被显式拒绝（需 TLS 或 RSA，`sa_std` 暂不提供；状态码 -103），`unknown auth plugin` 为 -104。属已知能力缺口，非 Phase 1 范围。
3. `db/core/postgres.sai` 头注释记载：每连接同时只能有一个结果集、新执行会替换旧结果集；值一律文本格式传输。属已知语义约束。
4. `db/storage/plugin_sqlite.sa` 头注释要求调用方自行串行化访问（同步 ABI，多 worker 下须专用 worker 或自行加锁）。属已知约束。
5. 本域无连接池、无 key-value 抽象、无迁移工具——缺口登记，不在 Phase 1 新建。
