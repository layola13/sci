# SA 标准库模块化 Phase 1 — 领域 E（net + http）报告

- 工作仓：盒上 `/content/kit-work/sci2-agentS1E`（sci2 副本，分支 `sa-optimize`，HEAD `be42fa97`）
- 日期：2026-11-22；领域 agent E
- 约束遵守：只做目录与模块边界整理；**未修复任何 bug，未跑任何构建与测试**（无 `zig build`、无测试套件）；**未 commit、未 push、未合并 main**；未动 `tests/` 夹具、未动 `src/`、未动其他域文件（除 §6 列出的 4 个文件各 1–2 行 import 引用更新，那是任务第 2 步明确授权的）。
- 背景数字纠正：任务称 sa_std 共 364 个文件，实测为 **363 个源码文件（.sa/.sai/.sal/.sla）+ `sa.mod` = 364 个文件**。

## 1. 模块映射表（旧路径 → 新路径）

44 个文件，16,307 行。Shim 列：Y = 旧路径留薄 shim（只含一行 `@import` 转发），N(.sai) = 旧路径无 shim（见 §4）。

### net 域（29 个文件，10,433 行）

| 旧路径 `sa_std/` | 新路径 `sa_std/` | Shim |
|---|---|---|
| net.sa | net/socket/net.sa | Y |
| net.sai | net/socket/net.sai | N(.sai) |
| net.sal | net/socket/net.sal | Y |
| net.sla | net/socket/net.sla | Y |
| netx.sa | net/netx.sa | Y |
| netx.sai | net/netx.sai | N(.sai) |
| netx.sal | net/netx.sal | Y |
| net_info.sai | net/net_info.sai | N(.sai) |
| net_info.sla | net/net_info.sla | Y |
| ip.sla | net/ip.sla | Y |
| icmp.sla | net/icmp.sla | Y |
| dns.sla | net/dns/dns.sla | Y |
| quic.sa | net/quic.sa | Y |
| quic.sai | net/quic.sai | N(.sai) |
| quic.sal | net/quic.sal | Y |
| quic.sla | net/quic.sla | Y |
| dtls.sa | net/dtls.sa | Y |
| dtls.sai | net/dtls.sai | N(.sai) |
| dtls.sal | net/dtls.sal | Y |
| tls.sla | net/tls.sla | Y |
| tls_client.sa | net/tls_client.sa | Y |
| tls_client.sai | net/tls_client.sai | N(.sai) |
| tls_server.sa | net/tls_server.sa | Y |
| tls_server.sai | net/tls_server.sai | N(.sai) |
| tls_server.sal | net/tls_server.sal | Y |
| tls_server.sla | net/tls_server.sla | Y |
| ws_client.sa | net/ws_client.sa | Y |
| ws_client.sai | net/ws_client.sai | N(.sai) |
| ws_client.sla | net/ws_client.sla | Y |

### http 域（15 个文件，5,874 行）

| 旧路径 `sa_std/` | 新路径 `sa_std/` | Shim |
|---|---|---|
| http.sla | http/http.sla | Y |
| http2.sa | http/http2.sa | Y |
| http2.sai | http/http2.sai | N(.sai) |
| http2.sal | http/http2.sal | Y |
| http_client.sai | http/client/http_client.sai | N(.sai) |
| http_cookie.sai | http/http_cookie.sai | N(.sai) |
| http_cookie.sla | http/http_cookie.sla | Y |
| http_proxy.sla | http/client/http_proxy.sla | Y |
| http_server.sai | http/server/http_server.sai | N(.sai) |
| plugin_http_async.sa | http/client/plugin_http_async.sa | Y |
| plugin_http_server.sa | http/server/plugin_http_server.sa | Y |
| plugin_http_server.sla | http/server/plugin_http_server.sla | Y |
| multipart.sai | http/request/multipart.sai | N(.sai) |
| url.sla | http/url.sla | Y |
| smtp.sla | http/smtp.sla | Y |

### 新增文件

- `sa_std/net/prelude.sa`、`sa_std/net/prelude.sal`：net 命名空间聚合（沿用既有 prelude 模式）。
- `sa_std/http/prelude.sa`、`sa_std/http/prelude.sal`：http 命名空间聚合。
- `sa_std/net/MANIFEST.md`、`sa_std/http/MANIFEST.md`：各域边界清单（公共模块、职责、允许的依赖方向）。
- 各子目录 `README.md`（8 个）：`net/socket/`、`net/tcp/`（保留）、`net/udp/`（保留）、`net/dns/`、`http/client/`、`http/server/`、`http/request/`、`http/response/`（保留）。

### 子目录取舍说明

- `net/tcp/`、`net/udp/`、`http/response/` 按用户提案建目录，但**目前是空目录（仅 README）**：TCP/UDP 没有独立文件，都在 4233 行的 `net.sa` 单体里；response 面仍在 `http_client.sai` / `http_server.sai` / `http.sla` 里。Phase 1 只定边界、不拆大文件，拆分是后续阶段的工作（见 §8 O5）。
- `net/socket/` 放 `net.*` 四件套（socket API 本体）；`net/dns/` 放 `dns.sla`；其余 net 文件（netx、net_info、ip、icmp、quic、dtls、tls、ws_client）在 `net/` 根目录——提案未给它们设子目录，不擅自增设。
- `http/client/`：`http_client.sai`、`http_proxy.sla`、`plugin_http_async.sa`；`http/server/`：`http_server.sai`、`plugin_http_server.sa/.sla`；`http/request/`：`multipart.sai`；`http/` 根目录放共享模块（`http.sla`、`http2.*`、`http_cookie.*`、`url.sla`、`smtp.sla`）。
- `smtp.sla` 是 SMTP 邮件客户端，不是 HTTP，按任务域清单放在 `http/` 根目录，清单中已注明它是未来 `net/mail/` 的候选（见 §8 O4）。

## 2. 各域边界清单

- `sa_std/net/MANIFEST.md`：公共模块表、子目录分工、依赖方向（net 可依赖 core/io/os/alloc/string/vec/ptr/hash/fmt/time/fs/encoding；禁依赖 db；`ws_client` 是唯一 net→http 例外，见 §7）。
- `sa_std/http/MANIFEST.md`：公共模块表、子目录分工、依赖方向（http 可依赖 core 与 net，禁依赖 db；`smtp.sla` 的归属说明；顶层 prelude 从未收录 http，见 §8 O2）。

## 3. 重复文件判定

- **本域内无重复文件**：44 个文件在顶层各只存在一份；同 stem 多扩展属于 companion set（分工明确：`.sa` 宏层、`.sai` extern 声明、`.sal` `#def` 布局、`.sla` SLA 常量层），不是重复。例如 `net` 四件套、`quic` 四件套、`tls_server` 四件套；`.sla` 常量文件与同名 `.sa` 内容不同（纯 `const` 声明，如 `net.sla` 的 AF_*、`quic.sla` 的 QuicError 分类）。
- **其他域存在同名顶层/子目录并存现象**（仅登记，不判定、不处理，非本域）：`ascii`、`binary_heap`、`btree_map`、`btree_set`、`cstring`、`duration`、`future`、`growvec`、`hash`、`hashmap`、`hashset`、`instant`、`iter`、`join_handle`、`manually_drop`、`mem`、`nonzero`、`option`、`panic`、`phantom_data`、`result`、`string`、`task`、`vec`、`vec_deque`、`prelude` 等约 27 个 basename 在顶层与某子目录同时出现。本次未 diff 其内容（非本域、且用户禁令要求不动其他域），留给对应域 agent 判定哪个是规范版本。

## 4. Re-export / shim 决策

SA 语言**没有独立的 re-export 语法**。`@import "path"` 是唯一的导入形式；聚合靠只含 `@import` 的文件实现：

- 先证：各子目录 `prelude.sa` / `prelude.sal` 就是这种聚合文件（如 `io/prelude.sa` 仅 1 行 `@import "bufio.sa"`，`sync/prelude.sa` 聚合 8 个文件）；`plugin_http_server.sla` 本身就是 2 行 shim（注释 + `@import "sa_std/plugin_http_server.sa"`）。
- 结论：**旧路径留薄 shim 转发到新位置**，`.sa` / `.sal` 用相对路径形式、`sla` 用 `sa_std/` 前缀形式（与各自文件既有惯例一致）。共 31 个 shim。
- **`.sai` 无 shim**：全树 363 个文件中没有任何 `.sai` 包含 `@import`（`.sai` 全是 `@extern` 声明，SLA 规范 §4 称之为独立的直接解析路径），故 `.sai` shim 未经验证、未创建。13 个 `.sai` 直接移动，旧路径失效，是本次唯一的 breaking change（影响见 §5）。
- Shim 双重包含安全性：编译器按规范路径去重的证据较强——移动前树内同一文件已通过多种拼写被引用（如 `core/slice.sa` 有 4 种拼写、`net.sai` 有 `net.sai` 与 `sa_std/net.sai` 两种、`alloc/vec.sa` 有 3 种），且移动前 0 悬空引用。**但未经构建验证**，Phase 2 必须用构建确认（见 §8 O7）。

## 5. Breaking change：`.sai` 旧路径失效的影响面

sa_std 内部的 `.sai` 引用已全部更新（§6），以下外部引用**未动**（tests 禁动、demos 未动），Phase 2 需更新：

- tests（4 处）：`tests/net_addr_family_constants.sla:26`、`tests/net_sockopt_passthrough.sla:16`、`tests/net_unix_addr_kind_constants.sla:13`、`tests/sendfile_loopback.sla:14`，均为 `sa_std/net.sai` → 应改为 `sa_std/net/socket/net.sai`。
- demos（4 处）：`demos/c/964_cookie_jar/main.sa:2`（`http_cookie.sai` → `sa_std/http/http_cookie.sai`）、`demos/c/965_tls_config/main.sa:2`（`tls_client.sai` → `sa_std/net/tls_client.sai`）、`demos/c/966_sockopt_loopback/main.sa:2`（`net.sai` → `sa_std/net/socket/net.sai`）、`demos/rosetta/964_multipart_checksum/main.sa:2`（`multipart.sai` → `sa_std/http/request/multipart.sai`）。
- 其余外部引用不受影响：tests 其余 69 处、demos 其余 5 处均通过 shim 解析（§9 验证）。examples、bench、tools 无引用。
- `src/`（Zig 宿主）与 `docs/` 中对本域文件名的提及均为注释/文档字符串，非 `@import`，未动，只记录。

## 6. 已更新的 `@import` 引用（共 29 行编辑 + 2 行删除）

- 移动文件内部（20 行）：`net/socket/net.sa:3-5`（`hash.sa`/`io.sal`/`os/fd.sa` → `../../` 前缀）；`net/dns/dns.sla:56`、`net/icmp.sla:55`（`net.sai` → `net/socket/net.sai`）；`net/net_info.sla:56/61/62`；`net/quic.sla:21`；`net/ws_client.sla:23`；`http/http.sla:55`；`http/http_cookie.sla:24`；`http/client/http_proxy.sla:111/114/119`；`http/smtp.sla:66/67`；`http/client/plugin_http_async.sa:3`、`http/server/plugin_http_server.sa:4`（`plugin_async.sa` → `../../plugin_async.sa`）；`http/server/plugin_http_server.sla:2`。
- 顶层 prelude（2 行编辑 + 2 行删除）：`prelude.sa:41-42` 的 `net.sa`/`netx.sa` 合并为 `@import "net/prelude.sa"`；`prelude.sal:38-39` 的 `net.sai`/`netx.sai` 合并为 `@import "net/prelude.sal"`。http 未加入顶层 prelude（见 §8 O2）。
- 其他域文件（2 个文件各 1 行，任务第 2 步授权的引用更新）：`sse.sla:63`（`http_client.sai` → `http/client/http_client.sai`）、`redis.sla:94`（`net.sai` → `net/socket/net.sai`）。除 import 行外未改动这两个文件。
- 其中 5 行是静态检查发现并纠正的：`net/socket/net.sa` 与两个 plugin 文件初版误用 `../`（指向 `net/` / `http/`），实应为 `../../`（文件在两级子目录下）；已修正，复查 0 悬空（§9）。
- 新 prelude 的聚合面：`net/prelude.sa` 聚合 7 个 `.sa` 模块、`net/prelude.sal` 聚合 12 个 `.sal`/`.sai`；`http/prelude.sa` 聚合 3 个 `.sa`、`http/prelude.sal` 聚合 6 个。注意：此前顶层 prelude 只暴露 `net.sa`/`netx.sa`，现在经 `net/prelude.sa` 也会暴露 quic/dtls/tls_client/tls_server/ws_client（opt-in facade，见 `prelude.sa` 头注释“Explicit public facade … opt-in”）。`.sla` 常量文件不进 prelude：全树无 `.sa` 导入 `.sla` 的先例，也无 `prelude.sla` 先例。

## 7. 依赖方向实测（移动前 import 图谱）

- net → core（`core/slice.sa`）、io（`io.sal`）、os（`os/fd.sa`）、alloc/string/vec/ptr/hash/fmt、time、fs、encoding/json（仅 net_info）、`status.sla`；无 db 依赖；无 crypto.sai 依赖。
- http → net（`net.sai`、`tls_client.sai`、`ip.sla`）、core、io、os/fd、fs、env、encoding、fmt、string/vec/ptr、`status.sla`、`plugin_async.sa`（仅两个 plugin 适配器）；无 db 依赖。
- **例外**：`ws_client` 在 net 域内，但其 `ws_client.sai` 头注释说明 WebSocket 收发 extern 在 `http_client.sai`（`sa_http_websocket_*`），即存在 net→http 边。已记入两域 MANIFEST；若日后收紧分层，要么 `ws_client` 移去 `http/client/`，要么 WebSocket extern 移去 `net/`。
- **tls 与 crypto 的交叉**：本域无任何文件 `@import` `crypto.sai`。交叉只在注释与 Zig 运行时层：`tls_client.sai` / `ws_client.sai` 注释称后端是 sci 运行时的 Zig `std.crypto.tls` / `std.crypto.Bundle`；`quic.sai` 注释称 ngtcp2 + GnuTLS（外部 C 库）。如未来出现 SA 层 crypto 依赖，须先记入 MANIFEST。
- `plugin_async.sla`（async 域，未动）仍按旧路径 import `plugin_http_async.sa` 与 `plugin_http_server.sla`，经 shim 继续解析。

## 8. 发现的缺陷清单（只记录，未修复）

- **D1（疑似真 bug）**：`sa_std/net/socket/net.sal` L9 `#def SA_NET_ERR_ACCESS = 4` 与 L5 `#def SA_NET_ERR_TIMEOUT = 4` 在同一 `SA_NET_ERR_*` 家族内撞值（该家族其余值 0–8 各不相同，9 尚未使用）。对照：`SA_NET_ERROR_CODE_*` 家族 0–28 无撞值。未修。
- **O1**：`.sai` shim 可行性未验证——Phase 2 需实测 `.sai` 是否接受 `@import`；若接受，可补 13 个 `.sai` shim 恢复旧路径，消除 §5 的 breaking change。
- **O2**：顶层 `prelude.sa` / `prelude.sal` 移动前就不含任何 http 文件（pre-existing 缺口）。Phase 1 未把 `http/prelude.*` 加入顶层 facade（避免擅自扩大公共面），由总协调决定是否加入。
- **O3**：shim 双重包含依赖编译器按规范路径去重（证据见 §4），须 Phase 2 构建验证；另需验证 `prelude.sa` 经 `net/prelude.sa` 暴露新增模块无符号冲突。
- **O4**：`smtp.sla` 是邮件协议而非 HTTP，暂放 `http/` 根目录；未来 `net/mail/` 是候选归宿，Phase 2+ 定。
- **O5**：`net/tcp/`、`net/udp/`、`http/response/` 为保留空目录；拆 `net.sa`（4233 行）与 response 模块是后续阶段工作，不属 Phase 1。
- **O6**：其他域顶层/子目录同名并存（§3 所列约 27 个 basename）是系统性现象，未判定、未处理，留给对应域 agent。
- **O7**：`sa_std` 移动前基线 0 悬空引用（全树 `@import` 均可解析），本次以此为基线对照。

## 9. 静态 `@import` 解析检查结果（移动后，脚本复核）

- 方法：自写解析脚本（`/tmp/verify_e.py`，盒上 /tmp，不在仓内），对每个 `@import "…"` 按“相对导入文件 → sa_std 根 → 去 `sa_std/` 前缀后相对 sa_std 根”三规则解析。
- **sa_std 全树：852 条 `@import`，0 悬空，0 自引用**（移动前基线亦为 0 悬空）。
- 映射核对：44/44 新路径存在；31/31 shim 存在且各含唯一 `@import` 指向新位置；13/13 旧 `.sai` 路径已不存在；顶层残留的 31 个同名文件全是 shim。
- 6 个 prelude 文件全部 import 可解析：顶层 `prelude.sa` / `prelude.sal`（经 `net/prelude.*`）、`net/prelude.sa`（7/7）、`net/prelude.sal`（12/12）、`http/prelude.sa`（3/3）、`http/prelude.sal`（6/6）。
- tests：69 处经 shim 解析，4 处悬空（§5 的 `net.sai` 引用）；demos：5 处经 shim 解析，4 处悬空（§5 的 `.sai` 引用）。examples、bench、tools：0 引用。
- **未做**：未跑任何构建与测试（用户亲令 Phase 1 不跑），故以上仅为静态解析结论；构建验证（shim 有效性、`.sai` 行为、prelude 聚合无冲突）留待 Phase 2。

## 10. 备注

- 用户 2026-11-22 新定方向（MEMORY 同步更新）：“先用 Zig 做标准库模块化与按需加载，稳定后再考虑 Rust 重写；导入同时支持符号级与模块级，底层统一为符号依赖图。” 本次的 `net/`、`http/` 目录与 prelude 聚合即按“模块级导入”方向留的边界，未做符号级改动。
- 执行说明：任务中途收到一条执行风险提示（针对一次仓库目录列表输出），此后未再运行任何 git 命令与仓库脚本；全部移动与编辑均为 plain `mv` 与自写 Python 脚本的文件操作，未运行构建、测试或仓库内脚本。工作树未 commit，待总协调处理。
