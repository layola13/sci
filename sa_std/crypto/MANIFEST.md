# crypto 域边界清单（MANIFEST）

- 域：密码学与编解码（cryptography / hashing / compression / secure transport）
- 位置：`sa_std/crypto/`
- Phase 1 状态：2026-11-22 已整理（分支 `sa-optimize`，工作仓 `sci2-agentS1F`，未 commit）
- 负责人域：F（db + crypto + testing + tree_sitter + 总清单）

## 1. 职责

本域提供密码学原语与编解码：

- 哈希与消息认证：`hash/`（SA 侧 DefaultHasher 宏群）；`crypto.sai`（md5/sha1/sha256/sha384/sha512、HMAC、PBKDF2、HKDF）。
- 口令与密钥环：`crypto.sai`（bcrypt、OS keyring）。
- 随机数：`crypto.sai` 内的 `sa_crypto_random_bytes` / `sa_deno_random_uuid`（独立模块待 Phase 2，见 §6）。
- 压缩编解码：`encoding/`（gzip / zlib / raw deflate / brotli）。
- 安全传输协议：`ssh.sai`（SSH 客户端 + 服务端，libssh2 / libssh）。

本域不提供：TLS（属 net 域，`tls*.sa`）、JWT（属 db 域 `db/core/jwt.sla`，消费本域）、通用编码（base64/JSON/TOML/YAML 属 encoding 域）。

## 2. 结构

```
sa_std/crypto/
  prelude.sa          # SA 侧公共面：crypto.sai、ssh.sai、hash/hash.sa（见 §5）
  prelude.sal         # @import "hash/hash.sal"
  crypto.sai          # 总接口：bcrypt、keyring、HMAC、md5/sha*、PBKDF2、HKDF、随机数、UUID
  ssh.sai             # SSH 客户端 + 服务端 extern 契约（Zig 实现见 §4）
  hash/               # 哈希面
    hash.sa           # DefaultHasher / RandomState / BuildHasherDefault 宏群（232 个宏）
    hash.sal          # DefaultHasher / RandomState 布局常量
  encoding/           # 编解码面
    compress.sai      # 压缩原语 extern 契约（gzip/zlib/deflate/brotli）
    compress.sla      # import 面（纯转发 .sai）
  random/             # 预留，空（见 §6）
```

### 模块映射表（旧路径 → 新路径）

| 旧路径 | 新路径 | 行数 | 说明 |
|---|---|---|---|
| `sa_std/crypto.sai` | `crypto/crypto.sai` | 155 | 总接口；无 shim（见 §7） |
| `sa_std/ssh.sai` | `crypto/ssh.sai` | 2886 字节 | SSH 契约；无 shim（见 §7） |
| `sa_std/hash.sa` | `crypto/hash/hash.sa` | 1486 | DefaultHasher 宏群；旧路径留 shim |
| `sa_std/hash.sal` | `crypto/hash/hash.sal` | 358 字节 | 布局常量；旧路径留 shim |
| `sa_std/compress.sai` | `crypto/encoding/compress.sai` | 658 字节 | 压缩契约；无 shim（见 §7） |
| `sa_std/compress.sla` | `crypto/encoding/compress.sla` | 18 | import 面；旧路径留 shim |

附带改动（移动必需的路径更新，非修 bug）：

- `crypto/hash/hash.sa`：`@import "core/slice.sal"` / `"core/rc.sal"` / `"core/arc.sal"` → `"../../core/…"`（`hash.sal` 同目录，不变）。
- `crypto/encoding/compress.sla`：`@import "sa_std/compress.sai"` → `"sa_std/crypto/encoding/compress.sai"`。
- 仓外唯一改动：`demos/rosetta/963_compress_checksum/main.sa` 的 `@import "sa_std/compress.sai"` → `"sa_std/crypto/encoding/compress.sai"`（`.sai` 无 shim，见 §7；这是本次移动中唯一一个 `sa_std` 以外的改动行）。

注意：`sa_std/core/hash.sa`（48 行，HASH_*/MAP_* 宏群）**不是**本文件的重复——见总清单 §重复判定口径（同名异义）。它留在 `core/`，不动。

## 3. 依赖方向

允许依赖：**core**（`core/slice.sal`、`core/rc.sal`、`core/arc.sal`）。

| 文件 | SA 侧 import | 说明 |
|---|---|---|
| `crypto/crypto.sai` | 无 | 纯 extern 声明；Zig 侧实现见 §4 |
| `crypto/ssh.sai` | 无 | 纯 extern 声明；Zig 侧 dlopen libssh2/libssh |
| `crypto/hash/hash.sa` | `hash.sal`、`../../core/slice.sal`、`../../core/rc.sal`、`../../core/arc.sal` | 仅 core |
| `crypto/hash/hash.sal` | 无 | 纯布局常量 |
| `crypto/encoding/compress.sai` | 无 | 纯 extern 声明 |
| `crypto/encoding/compress.sla` | `sa_std/crypto/encoding/compress.sai` | 仅本域 |

禁止依赖：io、net、http、db。本域被 `db/core/jwt.sla` 依赖（jwt → crypto），依赖方向为 db → crypto，不反向。

## 4. Zig 宿主侧（只记录，不动 `src/`）

- `crypto.sai` 的 extern 由 `src/runtime/sa_crypto*.zig` 实现（`sa_crypto.zig`、`sa_crypto_asym*.zig`、`sa_crypto_keyring.zig`、`sa_crypto_sign.zig` 等；bcrypt 走系统 libxcrypt，keyring 走 libsecret / Secret Service；缺库时返回状态 8 而非静默降级，见 `.sai` 头注释）。
- `ssh.sai` 的 extern 由 `src/runtime/sa_ssh.zig` 实现（客户端 libssh2、服务端 libssh，dlopen 绑定）。
- `compress.sai` 的 extern 由 `src/runtime/sa_compress.zig` 实现。
- 核查结论：`src/` 与 `build.zig` 中没有按文件路径硬编码引用上述 `.sai` 的地方；extern 按符号名链接，不按文件路径。因此移动文件不要求 Zig 侧改名。**但 Phase 2 必须构建验证**（新子目录能被编译器找到）。

## 5. Prelude 与公共面

- `crypto/prelude.sa` 聚合 SA 侧公共面：`crypto.sai`、`ssh.sai`、`hash/hash.sa`（沿用各子目录既有 prelude 模式；`.sai` 进 `.sa` prelude 有 `testing/prelude.sa` import `assert.sai` 的先例）。
- `crypto/prelude.sal`：`@import "hash/hash.sal"`。
- `.sla` 文件（`encoding/compress.sla`）**不进 `prelude.sa`**：全仓零个 `.sa` 文件 import `.sla` 文件，且不存在 `prelude.sla` 先例，按完整新路径单独 import。
- 顶层 `sa_std/prelude.sa` / `prelude.sal` 未改动：它们 import 的 `hash.sa` / `hash.sal` 已改为经旧路径 shim 转发，门面仍成立。是否把 `crypto/prelude.sa` 纳入顶层门面，是 Phase 2 决策。

## 6. 预留子目录

- `crypto/random/`（空，仅 `README.md`）：随机数面预留。现存随机数能力（`sa_crypto_random_bytes`、`sa_deno_random_uuid`）仍声明在 `crypto.sai` 内；独立随机模块待 Phase 2 从 `crypto.sai` 拆出时落地。

## 7. 兼容策略

- 旧路径留薄 shim（2 行：注释 + `@import`），沿用仓内既有模式。shim 清单：`hash.sa`、`hash.sal`、`compress.sla`。
- **`.sai` 文件无 shim**：全仓核查，零个 `.sai` 文件包含 `@import`，`.sai` shim 未经验证，不造先例。`.sai` 的 import 方全部可控：
  - `crypto.sai`：仅 `db/core/jwt.sla` import（已同步更新）。
  - `compress.sai`：`crypto/encoding/compress.sla`（已同步更新）+ `demos/rosetta/963_compress_checksum/main.sa`（已同步更新 1 行）。
  - `ssh.sai`：全仓零个 SA 侧 import 方（仅 Zig 宿主 `src/runtime/sa_ssh*.zig` 实现其 extern；它是公开接口，由用户程序直接 import）。
- 引用方核查（`@import` 全仓扫描，排除 `.zig-cache`）：`tests/compress_format_constants.sla` import 的是 `compress.sla`（经 shim 兼容），未动 `tests/`。

## 8. 待定决策（Phase 2，不在 Phase 1 裁决）

1. **`crypto.sai` 的拆分**：现一个文件横跨哈希（md5/sha*）、消息认证（HMAC/PBKDF2/HKDF）、口令（bcrypt）、密钥环、随机数、UUID 六类。目标结构 `hash/`、`random/`、`encoding/` 要求把它拆成按类分片的 `.sai`（如 `hash/hash.sai`、`random/random.sai`）；拆分是 Phase 2 工作，Phase 1 只把文件整体归位。
2. **`compress` 的归属**：现按任务指派放在 `crypto/encoding/`。压缩与密码学无本质关联，候选归属另有 `encoding/` 域（base64/JSON/TOML/YAML 的兄弟）；Phase 2 需一次裁决后定点。
3. **jwt.sla 的归属**：见 `db/MANIFEST.md` §8（db 与 crypto 的交叉决策）。
4. **顶层门面**：是否把 `crypto/prelude.sa` 纳入 `sa_std/prelude.sa`。

## 9. 发现的问题（未修复，仅记录）

1. `crypto.sai` 单文件横跨六类能力（见 §8.1），与目标结构 `hash/`、`random/`、`encoding/` 三分法不匹配——结构债，待拆分。
2. `ssh.sai` 全仓零个 SA 侧 import 方：它是公开接口，现状是“有实现、无仓内调用”。是否应有仓内 smoke 引用，由 crypto 域后续决定；不是 bug。
3. `crypto.sai` 头注释记载：bcrypt 哈希为标准 60 字符 `$2b$` 形式、cost 4..31；keyring 缺库时状态 8、缺条目时状态 3、缺 secret service 时状态 6；HMAC hex 截断时状态 9。属已知契约，非问题。
4. `compress.sai` 头注释记载：格式码 1=gzip、2=zlib、3=raw deflate、4=brotli；输出为 u64 buffer handle。属已知契约。
