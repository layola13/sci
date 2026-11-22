# time 域边界清单（MANIFEST）

域入口：`sa_std/time/prelude.sa`（.sa 聚合）、`sa_std/time/prelude.sal`（布局聚合）。
旧路径 shim：`sa_std/time.sa`、`time.sai`、`time.sal`、`time.sla`、`duration.sa`、`duration.sal`、`instant.sa`、`instant.sal`。

## 1. 公共模块

| 模块 | 文件 | 职责 | 宏数 |
|---|---|---|---|
| time（契约） | time/time.sai | Zig 后端 `sa_time_*` 的 @extern 声明（instant/unix/UTC/ISO/字段读写） | — |
| time（布局） | time/time.sal | Time_* 常量、TimeDate/Duration/Instant/SystemTime/SystemTimeError 布局 | — |
| time（宏） | time/time.sa | TIME_NOW_*/TIME_SLEEP_*/TIME_DURATION_*/TIME_INSTANT_*/TIME_SYSTEM_TIME_*、hash 集成 | 128 |
| time/duration | time/duration.sa/sal | Duration 命名空间 facade（仅 @import time.*，无自有宏） | 0 |
| time/instant | time/instant.sa/sal | Instant/SystemTime 命名空间 facade（仅 @import time.*，无自有宏） | 0 |
| time（SLA） | time/time.sla | SLA 类型层：struct Duration/Instant/SystemTime + fn thread_sleep | — |

合计：128 个宏；顶层 time.sa 850 行整体移入，未拆分（Duration/Instant 宏本就全在 time.sa 内，facade 只是命名空间入口）。

## 2. 职责

- 单调时钟、Unix 时间、UTC 日历（ISO 解析/格式化/字段读写）、sleep、Duration/Instant/SystemTime 算术与哈希。
- 不负责：定时器调度（timer.sla 在域外，依赖本域）、异步（async.sla 在域外，依赖本域）、格式化输出（fmt 域）。

## 3. 允许的依赖方向

```
time/time.sa  -> time（time.sal/time.sai）、hash（DEFAULT_HASHER_*/RANDOM_STATE_*）
time/duration -> time（time.sal/time.sa）
time/instant  -> time（time.sal/time.sa）
time/time.sla -> sa_std/time/time.sa、sa_std/core/result.sa（SLA 根相对路径）
time 整体    -> core（经 hash）、hash
time 整体 -/-> io、fmt、os、net、db、http、sync
```

- time 是叶子域：只依赖 hash（+ core 经 hash 传递）；不依赖 io/fmt/os。
- 反向依赖（谁依赖 time）：sync/{barrier,condvar,mpsc,mpsc_list,mutex,once,rwlock}（time.sai/time.sa）、
  thread.sa、dns/icmp/jwt/supervisor.sla（time.sai）、async.sla、timer.sla（time.sla）、
  duration.sa/instant.sa（顶层 shim 已转发）、tests（经 shim）。
  也就是说 sync 与 thread 的计时能力来自本域；改动 time.sai 会影响 sync 全域，须同步核查。

## 4. 内部依赖图

- time.sa：EXPAND TIME_*（内部闭包：TIME_DURATION_CHECKED_*、TIME_CHECKED_*）+ DEFAULT_HASHER_WRITE_DURATION/INSTANT/SYSTEM_TIME/UNIX_TIMESPEC_NS
  与 RANDOM_STATE_BUILD（hash.sa，经直接 @import）。
- duration.sa/instant.sa：纯 facade，无 EXPAND。
- time.sla：调 TIME_DURATION_FROM_MILLIS、TIME_DURATION_AS_MILLIS、TIME_NOW_NS、TIME_INSTANT_ELAPSED、
  TIME_NOW_UNIX_MS、TIME_THREAD_SLEEP_NS（均在 time.sa 内定义）；struct 布局与 time.sal 的 Duration/Instant/SystemTime #def 对应。

## 5. 边界规则

1. 新时间宏按前缀归属：TIME_*（time.sa）；Duration/Instant/SystemTime 的命名空间入口只放 facade 文件，不放实现宏。
2. time.sai/time.sal 是域内唯一契约/布局文件；SLA 侧的 struct 字段须与 .sal 布局 #def 保持一致（改一处必须改另一处，本次只移动未改内容）。
3. time 不得新增对 io/fmt/os/net/db/http/sync 的依赖；它是 sync/thread 的下层，方向不可反转。
4. 顶层 `duration.sa` / `instant.sa` 与 `time/duration.sa` / `time/instant.sa` 的重复问题已解决：
   两边内容除注释措辞与相对路径前缀外完全相同，规范版本定为 time/ 内，顶层改为 shim（见 DUPLICATES.md）。
5. 旧路径 shim 不得删除（sync/thread/dns 等仓内引用已改新路径，但 tests 与 1 个 demo 仍用 `sa_std/time.sa` 旧路径）。
