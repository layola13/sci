# SA DB Plugin vs SQLite

日期：2026-06-12
目的：用 SA 写同一组会员库 benchmark，对比 db 插件和 SQLite 的实际表现。

## 测试对象

- db 插件：`/home/vscode/projects/sa_plugins/sa_plugin_db/sap.json`
- SQLite：系统 `/lib/x86_64-linux-gnu/libsqlite3.so.0`
- SA：`sa 0.0.3.3`
- 数据：50,000 行会员，字段为 `id`、`plan`、`status`、`points` 四个 `u64`。

SQLite 测试也由 SA 编写，通过 `@extern sqlite3_*` 调用 C API。SQLite 链接时使用重命名后的 `libsa_std` 本地副本，避免 std 内 `sqlite3_step/finalize` stub 覆盖系统 SQLite。

## 结果摘要

5 轮中位数：

| 类别 | 最快者 | 证据 |
| --- | --- | --- |
| 新建数据库/schema | SQLite | 0.596 ms vs db 6.711 ms |
| 批量插入 50,000 行 | db 插件 | 19.012 ms vs SQLite 41.081 ms |
| 单次 SUM/COUNT 扫描 | 分裂 | SQLite 的 SUM 更快；db 的 COUNT 更快 |
| 全量更新 | db 插件 | 8.897 ms vs SQLite 9.838 ms |
| compact/vacuum | SQLite | 5.597 ms vs db 20.293 ms |
| verify/integrity | SQLite | 3.518 ms vs db 11.624 ms |
| 并发查询 4 worker | db 插件 | 48.385 ms vs SQLite 120.165 ms |
| 并发插入 4 worker | db 插件 | 55.618 ms vs SQLite 90.713 ms |

## 单线程明细

| 操作 | db 插件 | SQLite | 最快 |
| --- | ---: | ---: | --- |
| create/init | 6.711 ms | 0.596 ms | SQLite 约 11.3x |
| bulk insert | 19.012 ms | 41.081 ms | db 插件约 2.2x |
| sum before | 5.359 ms | 3.256 ms | SQLite 约 1.6x |
| update all | 8.897 ms | 9.838 ms | db 插件约 1.1x |
| sum after | 3.683 ms | 2.803 ms | SQLite 约 1.3x |
| count plan=1 | 1.108 ms | 2.253 ms | db 插件约 2.0x |
| compact/vacuum | 20.293 ms | 5.597 ms | SQLite 约 3.6x |
| verify/integrity | 11.624 ms | 3.518 ms | SQLite 约 3.3x |

## 并发明细

| 操作 | db 插件 | SQLite | 最快 |
| --- | ---: | ---: | --- |
| serial query, 100x SUM | 122.111 ms | 308.089 ms | db 插件约 2.5x |
| concurrent query, 4x25 SUM | 48.385 ms | 120.165 ms | db 插件约 2.5x |
| concurrent insert, 4x12,500 rows | 55.618 ms | 90.713 ms | db 插件约 1.6x |

## 技术解释

db 插件在批量插入和全量列更新上占优，因为 benchmark 直接传入按列布局的 raw bytes，避免了 SQLite 每行 bind/step/reset 的开销。这个优势适合 SA 内部生成的列式数据。

SQLite 在初始化、vacuum 和 integrity check 上更强。SQLite 的存储层、pager、WAL/锁机制和查询执行路径成熟得多；db 插件目前没有 SQL、索引、事务日志、查询优化器或崩溃恢复。

db 插件当前查询只保留 read-handle API。打开 read handle 时一次性复制只读列快照，后续 SUM/COUNT/MIN/MAX 在内存里扫描，所以复用句柄的串行/并发查询比 SQLite 更快；单次查询如果把打开快照也计入，SUM 仍可能输给 SQLite。

db 插件这次修复了同进程并发写：native 写入口现在用进程内互斥保护 metadata 读改写，所以 4 个 SA worker 并发插入能得到正确的 50,000 行。这个互斥只证明同进程 benchmark 正确，不等同于多进程事务隔离或 ACID。

## 选择建议

- 需要 SQL、索引、事务、崩溃恢复：选 SQLite。
- SA 程序内部已有列式数据，想快速落地小表批量写入或全量列更新：db 插件在本 benchmark 更快。
- 需要生产级长期存储：SQLite 仍明显更稳。

本次问题“查询速度，并发查询，并发插入，哪个最快？”的实测答案：单次 SUM SQLite 更快、单次 COUNT db 更快；复用 read handle 的串行/并发查询 db 插件最快；并发插入 db 插件最快。
