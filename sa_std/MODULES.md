# sa_std 模块总清单（MODULES.md）

- 范围：`sa_std/` 全部 363 个文件（Phase 1 前）→ 389 个文件（Phase 1 后，F 域整理部分）
- Phase 1 状态：2026-11-22，F 域（db / crypto / testing / tree_sitter）已整理；其余域的目录与文件现状如实登记，归属建议待各域 agent 确认
- 工作仓：`sci2-agentS1F`（分支 `sa-optimize`，HEAD `be42fa97`），未 commit
- 维护：本文件由 F 域 agent 起草；各域边界清单见各域 `MANIFEST.md`

> 读法：**现状**是静态扫描的事实（`@import` 图 + 文件清单）；**目标方向**只在 F 域是定稿，其余域标注“待确认”，由各域 agent 在自己的 MANIFEST 中定稿后回填。不要把本文件的“建议归属”当成已执行的移动。

## 1. 域总表

| 域 | 位置 | 职责（一句话） | 现状 import 边（出边） | Phase 1 状态 |
|---|---|---|---|---|
| core | `core/` + 顶层 shim 群 | 语言核心：Option/Result/Cell/Rc/Arc/迭代器/内存原语/任务原语 | → sync、→ 顶层 | 已有子目录；顶层大量 shim 指向它 |
| alloc | `alloc/` + 顶层 `vec.sa` / `string.sa` / `growvec.sa` 分层门面 | 堆分配容器：Vec/String/GrowVec | → core、→ 顶层 | 已有子目录；顶层文件是分层扩展（见 §5） |
| collections | `collections/` + 顶层实现文件 | 集合：map/set/heap/deque/链表 | → core、→ 顶层 | 已有子目录；实现在顶层，子目录是 shim（方向待翻转，见 §5） |
| string | 顶层（`string.sa` 等） | String 类型与格式化 | 待确认 | 未建子目录；归属待 string 域 agent 定 |
| fmt | 顶层（`fmt.sa` 等） | 格式化 | 待确认 | 未建子目录 |
| io | `io/` + 顶层 `io.sa` / `fs.sa` / `path.sa` 等 | 字节流、缓冲、文件系统、路径 | → 顶层 | 已有子目录（bufio/print）；其余待 io 域 agent 定 |
| sync | `sync/` | 同步原语：Mutex/RwLock/Condvar/Once/Atomic/MPSC/Barrier | → core、→ collections、→ 顶层 | 已有子目录 |
| task | 顶层（`executor.sla` 等）+ `core/task.sa` | 异步执行器与任务 | 待确认 | 未建子目录 |
| net | 顶层（`net.sa` / `quic` / `tls` / `dtls` / `ws` 等） | TCP/UDP/QUIC/TLS/DTLS/WebSocket/DNS | 待确认 | 未建子目录 |
| http | 顶层（`http.sla` / `http2` / `http_client` 等） | HTTP/1.1、HTTP/2、Cookie、代理、SSE | 待确认 | 未建子目录 |
| db | `db/` | 数据库客户端、嵌入式存储、JWT | → core（例外见 `db/MANIFEST.md` §3） | **Phase 1 已整理** |
| crypto | `crypto/` | 哈希、口令、密钥环、随机数、压缩、SSH | → core | **Phase 1 已整理** |
| encoding | `encoding/` | base64、JSON、TOML、YAML、bitpack | → core、→ 顶层 | 已有子目录 |
| ffi | `ffi/` + 顶层 `ffi.sa` | C 互操作、C 字符串 | → 顶层 | 已有子目录 |
| os | `os/` + 顶层 `env` / `process` | 文件描述符、环境变量、进程 | → core、→ 顶层 | 已有子目录 |
| time | `time/` + 顶层 `time.sa` | Duration/Instant/SystemTime、定时器 | → 顶层 | 已有子目录 |
| testing | `testing/` | 断言、Mock IO | （无出边） | **Phase 1 已确认：零移动** |
| text | `text/` + 顶层 `regex.*` | 正则表达式 | → core | 已有子目录 |
| tree_sitter | `tree_sitter/` | 代码分析接口 + tsgosa JS 值助手 | → 顶层（`string.sai` / `fmt.sai`） | **Phase 1 已整理** |
| marker | `marker/` + 顶层 `marker.sa` | PhantomData 等标记类型 | → 顶层 | 已有子目录 |
| mem | `mem/` + 顶层 `mem.sa` | ManuallyDrop；顶层 `mem.sa` 是 MEM_SIZE_OF/ALIGN_OF 宏群（见 §5） | → 顶层 | 已有子目录 |
| num | `num/` + 顶层 `num.sa` / `math.sa` | 整数、NonZero、数学函数 | → 顶层 | 已有子目录 |
| thread | `thread/` + 顶层 `thread.sa` | 线程、JoinHandle、TLS | → 顶层 | 已有子目录 |

既有子目录（Phase 1 前已存在）：alloc、collections、core、encoding、ffi、io、marker、mem、num、os、sync、testing、text、thread、time（15 个）。F 域新增：db、crypto、tree_sitter（3 个）。

## 2. 依赖方向总规则

### 2.1 分层（目标）

```
core            ← 最底层；只允许依赖 sync（已存在的一处例外，见 §2.3）与顶层遗留文件（过渡态）
alloc、collections、marker、mem、num、text、thread、time、ffi、os、io
                ← 依赖 core（或顶层门面文件）
sync            ← 依赖 core、collections
encoding        ← 依赖 core
string、fmt     ← 依赖 core、alloc（待确认）
task            ← 依赖 core、sync（待确认）
net             ← 依赖 core、os（待确认）
http            ← 依赖 net、encoding（待确认）
db              ← 依赖 core；例外：query/redis → net，core/jwt → crypto/encoding/time（已声明）
crypto          ← 依赖 core
tree_sitter     ← 依赖顶层 string.sai / fmt.sai（待 string/fmt 域归位后改为依赖对应域）
testing         ← 依赖无（mock 是 io 的替身，不得反向依赖 io）
```

### 2.2 硬规则

1. **不许成环**：任何域不得（直接或传递）依赖自身；`prelude.sa` 的聚合 import 不算依赖边，但不得用 prelude 掩盖环。
2. **只向下依赖**：上层域可以依赖下层域，下层域不得依赖上层域。`db`、`crypto`、`http` 不得被 `core` / `alloc` / `collections` / `sync` 依赖。
3. **`.sai` 是契约**：`.sai` 文件只含 `@extern` 声明，不含 `@import`（全仓现状：零个 `.sai` 含 `@import`）。移动 `.sai` 时不留 shim，同步更新其 import 方。
4. **`.sal` 是布局伴生**：`.sal` 只含 `#def` 布局常量与少量 `@import`；与同名 `.sa` 配对出现不是重复。
5. **`.sla` 不进 `.sa` prelude**：全仓现状：零个 `.sa` 文件 import `.sla` 文件，且不存在 `prelude.sla`。`.sla` 按完整路径单独 import。

### 2.3 已存在的跨层边（现状事实，登记在册）

| 边 | 证据 | 性质 |
|---|---|---|
| `core/sa_core.sa` → `sync/rwlock.sal`（同一文件 import 两次，36–37 行） | 静态扫描 | 例外 1：core 依赖 sync。另：重复 import 行本身登记为缺陷（见 §7）。 |
| `sync/mpsc_list.sa` → `collections/linked_list.sa` | 静态扫描 | sync 依赖 collections，属分层内允许的边。 |
| `encoding/bitpack.sla` → `core/slice.sa` | 静态扫描 | encoding 依赖 core，正常。 |
| `core/hash.sa` → `../hashmap.sa`（顶层） | 静态扫描 | core 依赖顶层遗留文件，过渡态。 |
| `core/box.sa` → `mem.sa`（顶层） | 静态扫描 | 同上。 |
| `db/query/redis.sla` → `net.sai` | 见 `db/MANIFEST.md` | 已声明例外（传输层未拆分）。 |
| `db/core/jwt.sla` → `crypto` / `encoding` / `time` | 见 `db/MANIFEST.md` | 已声明例外（JWT 本质是 crypto 应用）。 |
| 顶层文件 → 各子目录（138 条 import 指向 `core/`） | 静态扫描 | 过渡态：顶层门面/实现仍大量直引子目录文件。 |

## 3. 各域小节

### core
- 位置：`core/`（46 个文件）+ 顶层 shim 群（`option.sa`、`result.sa`、`panic.sa`、`task.sa`、`future.sa`、`iter.sa`、`ascii.sa` 及其 `.sal` 均系 1–3 行转发 shim）。
- 职责：Option/Result、Cell/RefCell、Rc/Arc/Weak、Box、迭代器、切片、内存原语（`sa_mem_copy/set`）、任务/waker、trait object、派生宏。
- 例外：`core/hash.sa` 不是顶层 `hash.sa` 的重复（见 §5）；`core/mem.sa` 不是顶层 `mem.sa` 的重复（见 §5）。

### alloc
- 位置：`alloc/`（`vec.sa`、`vec.sal`、`growvec.sa`、`growvec.sal`、`layout.sal`、`string.sa`、`prelude.*`）+ 顶层分层门面（`vec.sa`、`string.sa`、`growvec.sa`、`vec_grow.sla`、`vec_packed.sla`、`vec_runtime_macros.sa`、`growvec.sai`）。
- 层关系：子目录文件是运行时核，顶层文件 import 它们再扩展（见 §5）。

### collections
- 位置：`collections/`（`binary_heap.sa`、`btree_map.sa`、`btree_set.sa`、`hashmap.sa`、`hashset.sa`、`linked_list.sa`、`vec_deque.sa`、`prelude.*`）+ 顶层实现文件。
- 现状方向是反的：子目录 6 个文件是 1 行 shim（`@import "../xxx.sa"`），真正实现在顶层。collections 域 agent 在 Phase 2 可把实现移入子目录并把顶层改写为 shim；Phase 1 只登记，不翻转。

### string / fmt
- 位置：顶层。`string.sa`（12241 行 String 实现）、`string.sai`、`string.sal`、`string_format.sa`、`str.sla`；`fmt.sa`、`fmt.sai`、`fmt.sal`。
- 待 string/fmt 域 agent 定子目录与归属。注意：`alloc/string.sa` 只是 3 行 `STR_FROM_CONST` 宏，与顶层 `string.sa` 符号不重叠（见 §5）。

### io
- 位置：`io/`（`bufio.sa`、`buf_reader.sa`、`buf_writer.sa`、`print.sa`、`print.sai`、`prelude.*`）+ 顶层 `io.sa`、`io.sai`、`io.sal`、`fs.sa`、`fs.sai`、`fs.sal`、`path.sa`、`path.sal`、`term.sa`、`term.sai`、`term.sal`。
- 归属待 io 域 agent 定（`fs` / `path` / `term` 是否进 `io/`）。

### sync
- 位置：`sync/`（atomic、barrier、condvar、mpsc、mpsc_list、mutex、once、poison、rwlock + `prelude.*`）。
- 依赖：core、collections（`mpsc_list.sa` → `collections/linked_list.sa`）。

### task
- 位置：顶层。`task.sa`、`task.sai`、`task.sal`（shim → `core/task.*`）、`future.sa`、`future.sal`（shim → `core/future.*`）、`executor.sla`、`executor_test.sla`、`m_async.sa`、`m_async.sal`、`m_async.sla`、`libsa_async.sa`、`plugin_async.sa`、`plugin_async.sal`、`plugin_async.sla`、`async.sla`、`supervisor.sla`、`ctx.sla`（候选，见附录）。
- 待 task 域 agent 定子目录。

### net
- 位置：顶层。`net.sa`、`net.sai`、`net.sal`、`net.sla`、`netx.sa`、`netx.sai`、`netx.sal`、`net_info.sai`、`net_info.sla`、`ip.sla`、`dns.sla`、`icmp.sla`、`quic.sa`、`quic.sai`、`quic.sal`、`quic.sla`、`tls.sla`、`tls_client.sa`、`tls_client.sai`、`tls_server.sa`、`tls_server.sai`、`tls_server.sal`、`tls_server.sla`、`dtls.sa`、`dtls.sai`、`dtls.sal`、`ws_client.sa`、`ws_client.sai`、`ws_client.sla`、`smtp.sla`、`url.sla`（候选 net/http）。
- 待 net 域 agent 定子目录。`dtls` 与本清单 F 域交叉：只登记，不碰。

### http
- 位置：顶层。`http.sla`、`http2.sa`、`http2.sai`、`http2.sal`、`http_client.sai`、`http_cookie.sai`、`http_cookie.sla`、`http_proxy.sla`、`http_server.sai`、`multipart.sai`、`plugin_http_async.sa`、`plugin_http_server.sa`、`plugin_http_server.sla`、`sse.sla`（候选，见附录）。
- 待 http 域 agent 定子目录。

### db / crypto / testing / tree_sitter
- 见各域 `MANIFEST.md`（`db/MANIFEST.md`、`crypto/MANIFEST.md`、`testing/MANIFEST.md`、`tree_sitter/MANIFEST.md`）。

### encoding
- 位置：`encoding/`（`base64.sai`、`bitpack.sla`、`json.sa`、`json.sai`、`json.sal`、`json.sla`、`toml.sai`、`toml.sla`、`yaml.sai`、`yaml.sla`、`prelude.*`）。
- 备注：`encoding/prelude.sa` 目前只聚合 `json.sa`，base64/toml/yaml 未进 prelude；`encoding/prelude.sal` 是 0 字节空文件。登记供 encoding 域 agent 复核（Phase 1 不改）。

### ffi / os / time / text / marker / mem / num / thread
- `ffi/`：`cstring.sa`、`cstring.sal`、`prelude.*`；顶层 `ffi.sa`、`ffi.sal` 是实现，`cstring.sa` 是其门面。
- `os/`：`fd.sa`、`fd.sai`、`fd.sal`、`unix_ffi.sa`、`prelude.*`；顶层 `env.sa`、`env.sai`、`process.sa`、`process.sai`、`process.sal` 待 os 域 agent 定。
- `time/`：`duration.sa`、`duration.sal`、`instant.sa`、`instant.sal`、`prelude.*`；顶层 `time.sa`、`time.sai`、`time.sal`、`time.sla`、`timer.sla` 待 time 域 agent 定。
- `text/`：`regex.sa`、`regex.sai`、`regex.sal`、`regex.sla`、`prelude.*`。
- `marker/`：`phantom_data.sa`、`phantom_data.sal`、`prelude.*`；顶层 `marker.sa`、`marker.sal` 是实现。
- `mem/`：`manually_drop.sa`、`manually_drop.sal`、`prelude.*`；顶层 `mem.sa` 是 MEM_SIZE_OF/ALIGN_OF 宏群（见 §5），`mem.sal` 是其布局伴生。
- `num/`：`nonzero.sa`、`nonzero.sal`、`prelude.*`；顶层 `num.sa`、`num.sai`、`num.sal`、`num_u32.sla`、`math.sa`、`math.sai` 待 num 域 agent 定。
- `thread/`：`join_handle.sa`、`join_handle.sal`、`prelude.*`；顶层 `thread.sa`、`thread.sai`、`thread.sal`、`thread_local.sa`、`thread_local.sai` 待 thread 域 agent 定。

## 4. 顶层门面（`sa_std/prelude.sa` / `prelude.sal`）

- 顶层 `prelude.sa` 是显式公共门面聚合（文件头注释：“opt-in；编译器不隐式注入”），聚合 `core`、`alloc`、`collections`、`encoding`、`ffi`、`io`、`os`、`sync`、`text` 各子目录 prelude + 一批顶层文件。
- 现状：`db`、`crypto`、`testing`、`tree_sitter` 的 prelude **均未**纳入顶层门面；`hash.sa` / `hash.sal` 以单文件形式在门面内（现经旧路径 shim 转发到 `crypto/hash/`，门面仍成立）。
- Phase 1 不改动顶层门面。是否纳入新四域的 prelude，是 Phase 2 决策（由各域 MANIFEST 登记）。

## 5. 重复文件判定口径（全库统一）

本口径适用于各域都可能遇到的“顶层 vs 子目录同名文件”。判定以**引用情况与 diff 为准**，分五类；分类证据缺一不可：diff 结果 + 双方符号集（`@export` / `[MACRO]` / `#def` / `@extern`）+ 全仓 `@import` 引用计数（统计含 `sa_std/`、`tests/`、`demos/`，排除 `.zig-cache`）。

| 类别 | 判定条件 | 处理 | 例子 |
|---|---|---|---|
| A. 薄 shim（已解决） | 一方是 1–3 行纯 `@import` 转发 | 正规范 = 被指向的目标文件；**不删除 shim**（删了会断旧路径引用） | 顶层 `option.sa` → `core/option.sa`；`collections/binary_heap.sa` → `../binary_heap.sa` |
| B. 同名异义（不是重复） | 双方都是实质内容，符号集不重叠 | 两处都保留；清单注明“同名异义”；Phase 2 可考虑改名消歧，Phase 1 不动 | `core/hash.sa`（HASH_*/MAP_* 宏）vs `crypto/hash/hash.sa`（DefaultHasher 宏群）；顶层 `mem.sa`（MEM_SIZE_OF/ALIGN_OF 宏）vs `core/mem.sa`（`sa_mem_copy/set` + BOX_* 宏）；`alloc/string.sa`（`STR_FROM_CONST` 宏）vs 顶层 `string.sa`（String 实现） |
| C. 分层（不是重复） | 一方 `@import` 另一方并在其上扩展 | 保留分层，注明上下层关系；下层是运行时核，上层是宏门面/扩展 | 顶层 `vec.sa` import `alloc/vec.sa` 再扩展；顶层 `growvec.sa` import `alloc/growvec.sa` 再加 GROWVEC_* 宏 |
| D. 真重复（内容相同） | 符号集重叠且 diff 实质为空 | 以被引用更多的一方为规范，另一方改写为 A 类 shim；引用数相近时以子目录版本为规范（模块化方向是向子目录收敛） | 本次扫描：**零例**（全部同名对均非内容相同，见 §6） |
| E. 真冲突（内容分叉） | 符号集重叠但实现已分叉 | 不擅自合并；登记为缺陷，列 diff 要点与双方引用方，交用户或该域 agent 裁决 | 本次扫描：**零例** |

补充规则：

- `prelude.sa` / `prelude.sal` 每目录一份是按设计重复的，不算重复文件。
- `.sal` 与同名 `.sa` 配对（如 `vec.sa` / `vec.sal`）不是重复：`.sal` 是布局/ABI 伴生文件。`alloc/vec.sal`（`Vec_SIZE/ptr/cap/len`）与顶层 `vec.sal`（`Vec_data`）的 `#def` 不重叠，属互补。
- 判定为 B/C 类的，须在该域 MANIFEST 或本清单 §6 登记双方符号集要点；只凭文件名相同不得判定为重复。

## 6. 重复文件清查结果（本次扫描，2026-11-22）

扫描范围：`sa_std/` 全部 363 个文件，同名（basename）跨目录 42 组（含 `prelude.*`）。结论：**无 D 类、无 E 类**。全部已分类如下（A/B/C 类）：

| 同名文件 | 类别 | 正规范 / 层关系 | 证据 |
|---|---|---|---|
| `ascii.sa` / `ascii.sal` | A | `core/ascii.sa`（784 行）/ `core/ascii.sal`（34 行）；顶层是 shim | 顶层 2 行 / 1 行转发 |
| `future.sa` / `future.sal` | A | `core/future.sa`（777 行）；顶层是 shim | 顶层 2 行 / 1 行转发 |
| `iter.sa` / `iter.sal` | A | `core/iter.sa`（2805 行）；顶层是 shim | 顶层 2 行 / 1 行转发 |
| `option.sa` / `option.sal` | A | `core/option.sa`（833 行）；顶层是 shim | 顶层 2 行 / 1 行转发 |
| `result.sa` / `result.sal` | A | `core/result.sa`（718 行）；顶层是 shim | 顶层 2 行 / 1 行转发 |
| `panic.sa` / `panic.sal` | A | `core/panic.sa`（23 行）；顶层是 shim | 顶层 1 行转发 |
| `task.sa` / `task.sal` | A | `core/task.sa`（112 行）；顶层是 shim | 顶层 2 行 / 1 行转发 |
| `binary_heap.sa` | A（反向） | 顶层 `binary_heap.sa`（3004 行）是实现；`collections/binary_heap.sa` 是 1 行 shim → `../binary_heap.sa` | 方向待 collections 域翻转 |
| `btree_map.sa` / `btree_set.sa` | A（反向） | 顶层是实现（2320 / 1072 行）；`collections/` 内是 1 行 shim | 同上 |
| `hashmap.sa` / `hashset.sa` | A（反向） | 顶层是实现（2736 / 1059 行）；`collections/` 内是 1 行 shim | 同上 |
| `vec_deque.sa` | A（反向） | 顶层是实现（4925 行）；`collections/vec_deque.sa` 是 1 行 shim | 同上 |
| `cstring.sa` / `cstring.sal` | A | 正规范 `ffi.sa` / `ffi.sal`（顶层）；顶层 `cstring.*` 与 `ffi/cstring.*` 都是指向它的门面 | 两侧均为转发 |
| `duration.sa` / `duration.sal`、`instant.sa` / `instant.sal` | A | 正规范 `time.sa` / `time.sal`（顶层）；顶层与 `time/` 内文件都是门面 | 两侧均为转发 |
| `join_handle.sa` / `join_handle.sal` | A | 正规范 `thread.sa` / `thread.sal`（顶层）；两侧均为门面 | 两侧均为转发 |
| `manually_drop.sa` / `manually_drop.sal` | A | 正规范 `mem.sa` / `mem.sal`（顶层）；两侧均为门面 | 两侧均为转发 |
| `nonzero.sa` / `nonzero.sal` | A | 正规范 `num.sa` / `num.sal`（顶层）；两侧均为门面 | 两侧均为转发 |
| `phantom_data.sa` / `phantom_data.sal` | A | 正规范 `marker.sa` / `marker.sal`（顶层）；两侧均为门面 | 两侧均为转发 |
| `growvec.sa` | C 分层 | `alloc/growvec.sa`（运行时核，9 个 `@export`）→ 顶层 `growvec.sa`（GROWVEC_* 宏门面，import 子目录版再扩展） | 上层 import 下层 |
| `vec.sa` | C 分层 | `alloc/vec.sa`（969 行）→ 顶层 `vec.sa`（5784 行，import 子目录版再扩展） | 上层 import 下层 |
| `vec.sal` | B 互补 | `alloc/vec.sal`（`Vec_SIZE/ptr/cap/len`）与顶层 `vec.sal`（`Vec_data`）的 `#def` 不重叠 | 符号集不交 |
| `string.sa` | B 同名异义 | `alloc/string.sa` 仅 3 行 `STR_FROM_CONST` 宏；顶层 `string.sa`（12241 行）是 String 实现，不 import 前者 | 符号集不交 |
| `hash.sa` | B 同名异义 | `core/hash.sa`（48 行，HASH_*/MAP_* 宏 + import hashmap）vs 顶层 `hash.sa`（1486 行，DefaultHasher 宏群；现 `crypto/hash/hash.sa`） | 符号集不交 |
| `mem.sa` | B 同名异义 | 顶层 `mem.sa`（621 行，MEM_SIZE_OF/ALIGN_OF 宏群，无 `@export`）vs `core/mem.sa`（297 行，`sa_mem_copy/set/copy_nonoverlapping` + BOX_* 宏） | 符号集不交；两者被同一批文件同时 import（hashmap/io/binary_heap/array/vec_deque/ptr/ffi/sort/btree_map） |
| `prelude.sa` / `prelude.sal` | 按设计 | 每目录一份聚合文件，不算重复 | — |

## 7. 兼容策略（shim 规则）

1. **shim 形式**：旧路径留 2 行文件——1 行注释（注明 Phase 1 移动日期与新路径）+ 1 行 `@import`。`.sa` / `.sal` shim 用相对路径（如 `@import "core/option.sa"`）；`.sla` shim 用 `sa_std/` 前缀（如 `@import "sa_std/db/query/redis.sla"`）。两种写法均有仓内先例。
2. **`.sai` 不留 shim**：全仓零个 `.sai` 文件含 `@import`，`.sai` shim 未经验证。移动 `.sai` 时同步更新其全部 import 方（本次 `.sai` 的 import 方均在域内或仅 1 处 demo，见各 MANIFEST）。
3. **shim 保留期**：至少保留到 Phase 2 末。删除 shim 的前提：全仓 `@import` 扫描确认零引用旧路径（含 `tests/`、`demos/`、`docs/` 示例代码），且构建验证通过。
4. **双路径 import 风险**：同一程序同时 import 旧路径（shim）与新路径时，真实文件经两条拼写到达。既有门面已存在同类情形（顶层 `prelude.sa` 经 `core/prelude.sa` 与顶层 `option.sa` 两条路径到达同一份 `core/option.sa`，现行可用），故 shim 方案被采纳；但“shim + 真实路径同时 import 同一文件”仍是 Phase 2 构建验证项（见 §8）。
5. **顶层门面不追 shim**：`sa_std/prelude.sa` / `prelude.sal` 在 Phase 1 不改动；被移动文件的旧路径 shim 使门面继续成立。

## 8. 静态 `@import` 解析检查（Phase 1，F 域）

方法：Python 脚本静态解析全部 `@import "…"`，`sa_std/` 前缀按仓根解析，其余按 import 方所在目录相对解析；文件必须真实存在。排除 `.zig-cache`（构建产物）。

| 检查 | 移动前基线 | 移动后 | 结论 |
|---|---|---|---|
| `sa_std/` 内部 | 363 文件、796 条 import、**0 悬空** | 389 文件、834 条 import、**0 悬空** | 通过 |
| 全仓 `sa_std/` 前缀 import | 0 悬空 | 0 悬空 | 通过 |
| 全仓总悬空数 | 617 | 617 | 持平；全部是移动前已存在的两类（见下） |

移动后 617 条悬空的构成（均与本次移动无关）：

- 611 条在 `demos/`：包夹具（`demos/c/201–239`、`demos/rosetta/5xx` 等）使用包根相对 import 语义，朴素“按文件目录解析”会误判；属检查器语义局限，不是真实缺失。其中 `demos/*/298_eco_cryptography_simd/crypto/hash.sa` 的 `crypto/hash.sal` 是 demo 本地文件（该目录自带 `crypto/hash.sal`），与 `sa_std` 的 `hash.sal` 无关。
- 6 条在 `tests/deno_*_facade.sa`：指向仓外 `../../sa_plugins/sa_plugin_deno/deno.sal`（本仓无该路径），移动前已存在。

移动中发现并修复的一处（属移动必需的路径更新，非 bug 修复）：`tree_sitter/ts_string.sa` 的 `@import "string.sai"` / `"fmt.sai"` 在移入子目录后须改为 `"../string.sai"` / `"../fmt.sai"`（静态检查报 2 条悬空后修正，复查归零）。

未做的验证（Phase 1 禁令：不跑构建与测试）：

- 未跑 `zig build`、未跑任何测试套件；上述结论是静态路径解析，不是编译验证。
- Phase 2 必须验证：① 构建能找到新子目录（`SA_STD_DIR` 机制）；② 旧路径 shim 与新路径同时 import 时编译器去重行为；③ `tests/`（redis/jwt/compress/tree_sitter 相关）与 `demos/rosetta/963` 的回归。

## 9. 发现的缺陷总登记（未修复，仅记录）

F 域清单只登记与 F 域直接相关的缺陷；其余域的缺陷由各域 agent 登记。完整条目见各域 MANIFEST 的“发现的问题”一节：

- `db/MANIFEST.md` §9（5 条：redis→net 依赖、`mysql_client.sai` 的 -103/-104 能力缺口、postgres 单结果集约束、sqlite 同步串行化约束、无连接池）。
- `crypto/MANIFEST.md` §9（4 条：`crypto.sai` 六类合一待拆分、`ssh.sai` 零仓内调用、bcrypt/keyring 与压缩格式的已知契约）。
- `testing/MANIFEST.md` §6（3 条：mock_io 少调用、无运行器、断言面窄）。
- `tree_sitter/MANIFEST.md` §7（4 条：B 组 4 文件零仓内引用、A/B 两组同域待细分、`ts_host` 未接线、`ts_string` 的 JS quirk 保留）。

跨域登记（F 域扫描中发现、属他域文件，Phase 1 不动，仅知会）：

- `sa_std/core/sa_core.sa` 第 36–37 行重复 import 同一文件 `@import "../sync/rwlock.sal"` 两次。请 core 域 agent 复核（疑似复制粘贴残留；未验证是否影响编译）。
- `sa_std/encoding/prelude.sa` 只聚合 `json.sa`，base64/toml/yaml 未进 prelude；`encoding/prelude.sal` 是 0 字节空文件。请 encoding 域 agent 复核。

## 附录 A：顶层文件待归位清单（建议归属，待各域 agent 确认）

本附录列出 Phase 1 结束后仍在 `sa_std/` 顶层的全部文件（F 域移动后），按建议归属分组。“？”表示归属是建议而非定论；**本附录不产生移动动作**。

- **core（候选）**：`any.sa`、`any.sal`、`array.sa`、`borrow.sa`、`borrow.sal`、`char.sa`、`char.sal`、`cmp.sa`、`cmp.sal`、`control.sal`、`convert.sa`、`convert.sal`、`cow.sa`、`cow.sal`、`default.sa`、`error.sa`、`error.sal`、`mem.sa`（MEM_SIZE_OF/ALIGN_OF 宏群）、`mem.sal`、`ops.sa`、`ops.sal`、`pin.sa`、`pin.sal`、`ptr.sa`、`ptr.sal`、`rust_core.sa`、`rust_core.sal`、`slice_pool.sla ?`、`slot_pool.sla ?`、`status.sla ?`、`globals.sai ?`、`modstate.sai ?`、`identity.sai ?`、`rel_link.sla ?`、`oop.sal ?`（对象模型宏，与 `core/trait_object.sa` 互补；见附录 B）。
- **alloc**：`vec_grow.sla ?`、`vec_packed.sla ?`、`vec_runtime_macros.sa ?`、`growvec.sai`（顶层 `growvec.sa` 的布局伴生？待核查）。
- **collections（候选）**：`sort.sa ?`（排序，候选 collections 或 core）。
- **string**：`string.sa`、`string.sai`、`string.sal`、`string_format.sa`、`str.sla ?`。
- **fmt**：`fmt.sa`、`fmt.sai`、`fmt.sal`。
- **io（候选）**：`fs.sa`、`fs.sai`、`fs.sal`、`path.sa`、`path.sal`、`term.sa`、`term.sai`、`term.sal`。
- **task（候选）**：`executor.sla`、`executor_test.sla`、`m_async.sa`、`m_async.sal`、`m_async.sla`、`libsa_async.sa`、`plugin_async.sa`、`plugin_async.sal`、`plugin_async.sla`、`async.sla`、`supervisor.sla`、`ctx.sla`（见附录 B）。
- **net（候选）**：`net.sa`、`net.sai`、`net.sal`、`net.sla`、`netx.sa`、`netx.sai`、`netx.sal`、`net_info.sai`、`net_info.sla`、`ip.sla`、`dns.sla`、`icmp.sla`、`quic.sa`、`quic.sai`、`quic.sal`、`quic.sla`、`tls.sla`、`tls_client.sa`、`tls_client.sai`、`tls_server.sa`、`tls_server.sai`、`tls_server.sal`、`tls_server.sla`、`dtls.sa`、`dtls.sai`、`dtls.sal`、`ws_client.sa`、`ws_client.sai`、`ws_client.sla`、`smtp.sla`、`url.sla ?`。
- **http（候选）**：`http.sla`、`http2.sa`、`http2.sai`、`http2.sal`、`http_client.sai`、`http_cookie.sai`、`http_cookie.sla`、`http_proxy.sla`、`http_server.sai`、`multipart.sai`、`plugin_http_async.sa`、`plugin_http_server.sa`、`plugin_http_server.sla`、`sse.sla`（见附录 B）。
- **已归位（F 域，旧路径为 shim）**：`redis.sla`、`mysql_client.sla`、`postgres.sla`、`plugin_sqlite.sa`、`plugin_sqlite.sla`、`jwt.sla`、`hash.sa`、`hash.sal`、`compress.sla`、`tree_sitter.sla`、`ts_array.sa`、`ts_host.sa`、`ts_jsval.sa`、`ts_jsx.sa`、`ts_math.sa`、`ts_num.sa`、`ts_object.sa`、`ts_promise.sa`、`ts_string.sa`、`ts_unicode.sa`（以上均为 2 行 shim，转发到新路径）。
- **已归位（F 域，旧路径已删除、无 shim）**：`mysql_client.sai`、`postgres.sai`、`crypto.sai`、`ssh.sai`、`compress.sai`、`tree_sitter.sai`、`ts_host.sai`、`ts_unicode.sai`（`.sai` 无 shim，见 §7 规则 2）。
- **顶层保留**：`sa.mod`（包清单）、`prelude.sa`、`prelude.sal`（顶层门面）。
- **顶层 shim 群（指向子目录，早于 Phase 1 存在）**：`ascii.sa`、`ascii.sal`、`future.sa`、`future.sal`、`iter.sa`、`iter.sal`、`option.sa`、`option.sal`、`result.sa`、`result.sal`、`panic.sa`、`panic.sal`、`task.sa`、`task.sal`、`cstring.sa`、`cstring.sal`、`duration.sa`、`duration.sal`、`instant.sa`、`instant.sal`、`join_handle.sa`、`join_handle.sal`、`manually_drop.sa`、`manually_drop.sal`、`nonzero.sa`、`nonzero.sal`、`phantom_data.sa`、`phantom_data.sal`。

## 附录 B：F 域“其他”文件的归属说明

任务指派的“其他”文件（`oop.sal`、`sse.sla`、`ctx.sla`、`dtls`）处理如下——**Phase 1 均保留在顶层原位，只定归属建议，不移动**（避免碰他域文件）：

- `oop.sal`（1934 字节）：单指针单继承对象模型宏（`CLASS_NEW` / `VCALL_*`），与 `core/trait_object.sa` 的胖指针 `DYN_*` 互补。无 import；引用方：`tests/oop_macros_fixture_sa`。建议归属：**core**（候选），待 core 域 agent 定。
- `sse.sla`（24434 字节）：Server-Sent Events 解析与客户端。依赖 `sa_std/http_client.sai`（http 域）+ `string.sa` / `vec.sa` / `core/slice.sa` / `ptr.sa`。引用方：`tests/sse_parser.sla`、`tests/sse_http_loopback.sla`。建议归属：**http**（候选），待 http 域 agent 定。
- `ctx.sla`（965 字节）：context 取消（Done-channel 惯用法，`done_new` / `done_signal` / `is_done`）。无 import；全仓零个 SA 侧引用方。建议归属：**task**（候选），待 task 域 agent 定。
- `dtls.sa` / `dtls.sai` / `dtls.sal`：与 net 域交叉。按任务要求**只记不碰**：不移动、不改 import、不写归属建议。
